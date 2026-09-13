/*
 * File: video_prefetch_coordinator.dart
 * Description: Adaptive sliding-window background chunk prefetcher with seek-eviction and priority scheduling.
 */

import 'dart:async';
import 'dart:typed_data';
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

  final Map<String, _PrefetchSession> _sessions = {};
  PrefetchChunkDownloader? _downloaderForTesting;

  /// Creates a VideoPrefetchCoordinator with an optional lookahead window size.
  VideoPrefetchCoordinator({this.prefetchWindowSize = 2});

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
        final bytes = await _downloadChunk(record, chunkIdx, session.chunkMap);
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
      }
    }
  }

  Future<Uint8List> _downloadChunk(
    FileRecord record,
    int chunkIdx,
    Map<int, ChunkInfo>? chunkMap,
  ) async {
    if (_downloaderForTesting != null) {
      return await _downloaderForTesting!(record, chunkIdx, RequestPriority.background);
    }

    final telegram = ServiceLocator.instance.telegram;
    if (chunkMap != null) {
      final target = chunkMap[chunkIdx + 1] ?? chunkMap[chunkIdx];
      if (target != null && target.fileId != null && target.fileId!.isNotEmpty) {
        return await telegram.downloadByFileId(target.fileId!, RequestPriority.background);
      }
    }

    if (record.chunkCount == 1 && chunkIdx == 0 && record.fileId.isNotEmpty) {
      return await telegram.downloadByFileId(record.fileId, RequestPriority.background);
    }

    throw StateError('Cannot download chunk $chunkIdx for ${record.fileId} without valid metadata');
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
    }
    for (final session in active) {
      try {
        await session.workerCompleter?.future;
      } catch (_) {}
    }
  }
}
