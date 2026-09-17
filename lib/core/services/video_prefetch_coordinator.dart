/*
 * File: video_prefetch_coordinator.dart
 * Description: Adaptive sliding-window background chunk prefetcher with seek-eviction and priority scheduling.
 */

import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import '../models/chunk_info.dart';
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import 'service_locator.dart';
import 'telegram_rate_limiter.dart';
import 'video_chunk_cache_manager.dart';

/// Callback signature for downloading chunks (supports unit testing).
typedef PrefetchChunkDownloader = Future<Uint8List> Function(
  FileRecord record,
  int chunkIndex,
  RequestPriority priority,
);

class _PrefetchSession {
  final FileRecord record;
  Map<int, ChunkInfo>? chunkMap;
  int currentPlaybackChunk;
  bool isCancelled = false;
  final Set<int> inFlightOrCompleted = {};
  final Map<int, int> inFlightBytes = {};
  final Map<int, int> inFlightTotals = {};
  final Map<int, CancelToken> inFlightCancelTokens = {};
  Completer<void>? workerCompleter;

  _PrefetchSession({
    required this.record,
    required this.currentPlaybackChunk,
    this.chunkMap,
  });
}

/// Adaptive prefetch coordinator that downloads ahead using a sliding window.
///
/// Features:
/// - Sliding window of [prefetchWindowSize] chunks (default 2).
/// - Prioritizes playback: prefetches run at [RequestPriority.background].
/// - Dynamic re-anchoring on seek: old prefetch queue is cancelled immediately,
///   and a new window is opened around the seek target.
class VideoPrefetchCoordinator {
  /// Lookahead window size (number of chunks to prefetch ahead).
  final int prefetchWindowSize;

  /// Listenable notifier bumped whenever in-flight prefetch progress updates.
  final ValueNotifier<int> prefetchProgressNotifier = ValueNotifier(0);

  final Map<String, _PrefetchSession> _sessions = {};
  PrefetchChunkDownloader? _downloaderForTesting;

  /// Creates a VideoPrefetchCoordinator with an optional lookahead window size.
  VideoPrefetchCoordinator({this.prefetchWindowSize = 2});

  /// Returns in-flight downloaded bytes across chunks currently being prefetched for [fileId].
  int getInFlightBytes(String fileId) {
    final session = _sessions[fileId];
    if (session == null || session.isCancelled) return 0;
    return session.inFlightBytes.values.fold(0, (sum, b) => sum + b);
  }

  /// Returns map of chunkIndex -> progress fraction (0.0 .. 1.0) for in-flight prefetch chunks.
  Map<int, double> getInFlightFractions(String fileId) {
    final session = _sessions[fileId];
    if (session == null || session.isCancelled) return const {};
    final result = <int, double>{};
    session.inFlightBytes.forEach((chunkIdx, received) {
      final total = session.inFlightTotals[chunkIdx] ?? (19 * 1024 * 1024);
      if (total > 0) {
        result[chunkIdx] = (received / total).clamp(0.0, 1.0);
      }
    });
    return result;
  }

  /// Overrides the chunk download execution for unit test isolation.
  void setDownloaderForTesting(PrefetchChunkDownloader? downloader) {
    _downloaderForTesting = downloader;
  }

  /// Notifies the coordinator that [requestedChunk] is being actively played/streamed.
  ///
  /// If [requestedChunk] represents a non-sequential jump (seek), any ongoing
  /// background prefetch for old positions is aborted and re-anchored.
  void onChunkRequested(
    FileRecord record,
    int requestedChunk, {
    Map<int, ChunkInfo>? chunkMap,
  }) {
    if (record.chunkCount <= 1) return;

    final fileId = record.fileId;
    final session = _sessions[fileId];

    if (session == null) {
      final newSession = _PrefetchSession(
        record: record,
        currentPlaybackChunk: requestedChunk,
        chunkMap: chunkMap,
      );
      _sessions[fileId] = newSession;
      _startWorker(newSession);
    } else {
      session.chunkMap = chunkMap ?? session.chunkMap;

      // Detect non-sequential seek / scrub
      final isSeek = (requestedChunk - session.currentPlaybackChunk).abs() > 1 ||
          requestedChunk < session.currentPlaybackChunk;

      if (isSeek) {
        AppLogger.d(
          'Seek detected on $fileId (from ${session.currentPlaybackChunk} to $requestedChunk). Resetting prefetch queue.',
          tag: 'VideoPrefetchCoordinator',
        );
        // Abort existing worker and clear pending chunks
        session.isCancelled = true;
        for (final token in session.inFlightCancelTokens.values) {
          token.cancel('Prefetch seek re-anchor');
        }
        session.inFlightCancelTokens.clear();
        final newSession = _PrefetchSession(
          record: record,
          currentPlaybackChunk: requestedChunk,
          chunkMap: session.chunkMap,
        );
        _sessions[fileId] = newSession;
        _startWorker(newSession);
      } else {
        session.currentPlaybackChunk = requestedChunk;
        _startWorker(session);
      }
    }
  }

  void _startWorker(_PrefetchSession session) {
    if (session.workerCompleter != null && !session.workerCompleter!.isCompleted) {
      // Worker is already running and will check updated currentPlaybackChunk
      return;
    }

    final completer = Completer<void>();
    session.workerCompleter = completer;

    unawaited(() async {
      try {
        await _runPrefetchLoop(session);
      } catch (e) {
        AppLogger.w('Prefetch loop error for ${session.record.fileId}: $e',
            tag: 'VideoPrefetchCoordinator');
      } finally {
        completer.complete();
      }
    }());
  }

  Future<void> _runPrefetchLoop(_PrefetchSession session) async {
    final record = session.record;
    final fileId = record.fileId;

    while (!session.isCancelled) {
      final cur = session.currentPlaybackChunk;
      final maxChunk = record.chunkCount - 1;
      int? nextChunkToFetch;

      for (int i = 1; i <= prefetchWindowSize; i++) {
        final target = cur + i;
        if (target > maxChunk) break;
        if (!session.inFlightOrCompleted.contains(target)) {
          nextChunkToFetch = target;
          break;
        }
      }

      if (nextChunkToFetch == null) {
        // All chunks in current window are either cached, in-flight, or complete
        break;
      }

      final chunkIdx = nextChunkToFetch;

      // 1. Check if already cached on disk
      final cached = await VideoChunkCacheManager.instance.getCachedChunk(fileId, chunkIdx);
      if (session.isCancelled) break;

      if (cached != null && cached.existsSync()) {
        session.inFlightOrCompleted.add(chunkIdx);
        continue;
      }

      session.inFlightOrCompleted.add(chunkIdx);

      try {
        final bytes = await _downloadChunk(session, chunkIdx);
        if (session.isCancelled) break;

        await VideoChunkCacheManager.instance.saveChunk(fileId, chunkIdx, bytes);
        if (session.isCancelled) break;
        AppLogger.d(
          'Prefetched chunk $chunkIdx for $fileId (${bytes.length} bytes)',
          tag: 'VideoPrefetchCoordinator',
        );
      } catch (e) {
        if (!session.isCancelled) {
          AppLogger.w('Failed to prefetch chunk $chunkIdx for $fileId: $e',
              tag: 'VideoPrefetchCoordinator');
        }
        session.inFlightOrCompleted.remove(chunkIdx);
        break;
      } finally {
        session.inFlightBytes.remove(chunkIdx);
        session.inFlightTotals.remove(chunkIdx);
        prefetchProgressNotifier.value++;
      }
    }
  }

  Future<Uint8List> _downloadChunk(
    _PrefetchSession session,
    int chunkIdx,
  ) async {
    final record = session.record;
    final chunkMap = session.chunkMap;

    if (_downloaderForTesting != null) {
      return await _downloaderForTesting!(record, chunkIdx, RequestPriority.background);
    }

    final telegram = ServiceLocator.instance.telegram;
    DateTime lastEmit = DateTime.now();

    void onProgress(int received, int total) {
      if (session.isCancelled) return;
      session.inFlightBytes[chunkIdx] = received;
      if (total > 0) session.inFlightTotals[chunkIdx] = total;

      final now = DateTime.now();
      if (now.difference(lastEmit).inMilliseconds >= 80) {
        lastEmit = now;
        prefetchProgressNotifier.value++;
      }
    }

    String? targetFileId;
    if (chunkMap != null) {
      final target = chunkMap[chunkIdx + 1] ?? chunkMap[chunkIdx];
      if (target != null && target.fileId != null && target.fileId!.isNotEmpty) {
        targetFileId = target.fileId;
      }
    } else if (record.chunkCount == 1 && chunkIdx == 0 && record.fileId.isNotEmpty) {
      targetFileId = record.fileId;
    }

    if (targetFileId != null) {
      final cancelToken = CancelToken();
      session.inFlightCancelTokens[chunkIdx] = cancelToken;
      try {
        return await telegram.downloadByFileIdWithProgress(
          targetFileId,
          priority: RequestPriority.background,
          onReceiveProgress: onProgress,
          cancelToken: cancelToken,
        );
      } finally {
        session.inFlightCancelTokens.remove(chunkIdx);
      }
    }

    throw StateError('Cannot download chunk $chunkIdx for ${record.fileId} without valid metadata');
  }

  /// Sets mock in-flight progress for testing.
  void setMockInFlightProgressForTesting(
    String fileId,
    int chunkIdx,
    int received,
    int total,
  ) {
    var session = _sessions[fileId];
    if (session == null) {
      session = _PrefetchSession(
        record: FileRecord(
          fileId: fileId,
          name: 'test.mp4',
          metadataMessageId: 1,
          sizeMb: 50.0,
          mimeType: 'video/mp4',
          uploadedAt: DateTime(2026),
          chunkCount: 3,
          sha256Hash: 'hash',
        ),
        currentPlaybackChunk: 0,
      );
      _sessions[fileId] = session;
    }
    session.inFlightBytes[chunkIdx] = received;
    session.inFlightTotals[chunkIdx] = total;
    prefetchProgressNotifier.value++;
  }

  /// Returns a Future that completes when the current prefetch worker for [fileId] finishes its loop (for testing).
  Future<void>? waitForWorkerForTesting(String fileId) {
    return _sessions[fileId]?.workerCompleter?.future;
  }

  /// Cancels any active prefetch workers and drops cached session state for [fileId].
  Future<void> cancelForFile(String fileId) async {
    final session = _sessions.remove(fileId);
    if (session != null) {
      session.isCancelled = true;
      for (final token in session.inFlightCancelTokens.values) {
        token.cancel('Prefetch cancelled for $fileId');
      }
      session.inFlightCancelTokens.clear();
      session.inFlightBytes.clear();
      session.inFlightTotals.clear();
      prefetchProgressNotifier.value++;
      try {
        await session.workerCompleter?.future;
      } catch (_) {}
    }
  }

  /// Cancels all active prefetch sessions across all files.
  Future<void> cancelAll() async {
    final active = _sessions.values.toList();
    _sessions.clear();
    for (final session in active) {
      session.isCancelled = true;
      for (final token in session.inFlightCancelTokens.values) {
        token.cancel('All prefetching cancelled');
      }
      session.inFlightCancelTokens.clear();
      session.inFlightBytes.clear();
      session.inFlightTotals.clear();
    }
    prefetchProgressNotifier.value++;
    for (final session in active) {
      try {
        await session.workerCompleter?.future;
      } catch (_) {}
    }
  }
}
