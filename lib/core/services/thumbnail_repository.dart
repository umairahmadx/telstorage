/*
 * File: thumbnail_repository.dart
 * Description: Two-tiered LRU memory and disk thumbnail repository providing synchronous zero-latency memory cache hits and background network/disk deduplication.
 */

import 'dart:async';
import 'dart:collection';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import '../utils/thumbnail_helper_native.dart'
    if (dart.library.js_interop) '../utils/thumbnail_helper_web.dart';
import 'telegram_rate_limiter.dart';
import 'telegram_service.dart';

/// Internal model representing a queued or active thumbnail download request.
class _ThumbnailRequest {
  final FileRecord file;
  final Completer<dynamic> completer;
  final bool isPriority;
  bool isCancelled = false;

  _ThumbnailRequest({
    required this.file,
    required this.completer,
    this.isPriority = false,
  });
}

/// Central repository managing high-speed LRU memory and disk cached media thumbnails with priority queuing.
class ThumbnailRepository {
  final TelegramService _telegram;

  /// Active downloads map returning identical Future for concurrent duplicate requests.
  final Map<String, Future<dynamic>> _activeDownloads = {};

  /// Pending LIFO queue of thumbnail download requests.
  final List<_ThumbnailRequest> _pendingQueue = [];

  /// In-flight thumbnail request currently executing network/disk fetch.
  final Map<String, _ThumbnailRequest> _inFlightRequests = {};

  /// Whether the queue is currently suspended (e.g. during video streaming or full-image viewing).
  bool _isPaused = false;

  /// Bounded concurrency for thumbnail network downloads (never congests network pipe).
  static const int _maxConcurrentDownloads = 1;

  /// Active in-flight worker count.
  int _activeCount = 0;

  /// Maximum number of thumbnail payloads kept in high-speed RAM (~6-8 MB total).
  static const int maxMemoryCacheSize = 200;

  /// High-speed LRU memory cache storing binary thumbnail bytes for zero-latency scroll rendering.
  final LinkedHashMap<String, Uint8List> _memoryCache = LinkedHashMap();

  /// Constructs ThumbnailRepository.
  ThumbnailRepository(this._telegram);

  /// Whether thumbnail downloading is currently paused.
  bool get isPaused => _isPaused;

  /// Number of requests currently waiting in the priority queue.
  int get pendingQueueLength => _pendingQueue.length;

  /// Synchronously checks if thumbnail bytes are available in memory LRU cache.
  Uint8List? getMemoryCachedBytes(String fileId) {
    if (_memoryCache.containsKey(fileId)) {
      final bytes = _memoryCache.remove(fileId)!;
      _memoryCache[fileId] = bytes; // MRU promotion
      return bytes;
    }
    return null;
  }

  /// Adds thumbnail bytes to the LRU memory cache, evicting oldest item if capacity is reached.
  void addToMemoryCache(String fileId, Uint8List bytes) {
    if (_memoryCache.containsKey(fileId)) {
      _memoryCache.remove(fileId);
    } else if (_memoryCache.length >= maxMemoryCacheSize) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[fileId] = bytes;
  }

  /// Clears the entire memory cache and pending queue.
  void clearMemoryCache() {
    _memoryCache.clear();
    _activeDownloads.clear();
    for (final req in _pendingQueue) {
      req.isCancelled = true;
      if (!req.completer.isCompleted) {
        req.completer.complete(null);
      }
    }
    _pendingQueue.clear();
  }

  /// Cancels an unfulfilled thumbnail request when its widget scrolls off-screen.
  void cancelThumbnailRequest(String fileId) {
    // 1. Remove from pending queue
    _pendingQueue.removeWhere((req) {
      if (req.file.fileId == fileId) {
        req.isCancelled = true;
        if (!req.completer.isCompleted) {
          req.completer.complete(null);
        }
        return true;
      }
      return false;
    });

    // 2. If in-flight, mark cancelled
    final inFlight = _inFlightRequests[fileId];
    if (inFlight != null) {
      inFlight.isCancelled = true;
      if (!inFlight.completer.isCompleted) {
        inFlight.completer.complete(null);
      }
    }

    _activeDownloads.remove(fileId);
  }

  /// Suspends background thumbnail downloading during high-priority tasks (e.g. video streaming, gallery viewing).
  void pauseDownloads() {
    _isPaused = true;
    AppLogger.d('Thumbnail queue paused', tag: 'ThumbnailRepository');
  }

  /// Resumes background thumbnail downloading.
  void resumeDownloads() {
    if (!_isPaused) return;
    _isPaused = false;
    AppLogger.d('Thumbnail queue resumed', tag: 'ThumbnailRepository');
    _pumpQueue();
  }

  /// Evicts a thumbnail from memory and deletes its cached disk files.
  Future<void> evict(String fileId) async {
    cancelThumbnailRequest(fileId);
    _memoryCache.remove(fileId);
    _activeDownloads.remove(fileId);
    await ThumbnailHelper.deleteCachedThumbnail(fileId);
  }

  /// Current number of items in memory cache.
  int get memoryCacheCount => _memoryCache.length;

  /// Retrieves thumbnail data (memory bytes on fast-hit, cached disk path on native), downloading if necessary.
  Future<dynamic> getThumbnailData(FileRecord file, {bool isPriority = false}) {
    if (file.thumbnailFileId == null) return Future<dynamic>.value(null);

    // 1. Fast path: Check synchronous in-memory LRU cache
    final memHit = getMemoryCachedBytes(file.fileId);
    if (memHit != null) return Future<dynamic>.value(memHit);

    // 2. Check active in-flight or existing queued future to deduplicate
    if (_activeDownloads.containsKey(file.fileId)) {
      return _activeDownloads[file.fileId]!;
    }

    // 3. Check if already waiting in pending queue
    for (int i = 0; i < _pendingQueue.length; i++) {
      if (_pendingQueue[i].file.fileId == file.fileId) {
        if (isPriority) {
          final req = _pendingQueue.removeAt(i);
          _pendingQueue.insert(0, req);
          return req.completer.future;
        }
        return _pendingQueue[i].completer.future;
      }
    }

    final completer = Completer<dynamic>();
    final request = _ThumbnailRequest(
      file: file,
      completer: completer,
      isPriority: isPriority,
    );

    _activeDownloads[file.fileId] = completer.future;

    // LIFO priority: Newly rendered items jump to index 0 so currently visible items download first.
    _pendingQueue.insert(0, request);

    _pumpQueue();

    return completer.future;
  }

  /// Pumps queued requests subject to concurrency limits and pause state.
  void _pumpQueue() {
    if (_isPaused) return;
    if (_activeCount >= _maxConcurrentDownloads) return;
    if (_pendingQueue.isEmpty) return;

    final request = _pendingQueue.removeAt(0);
    if (request.isCancelled) {
      _activeDownloads.remove(request.file.fileId);
      _pumpQueue();
      return;
    }

    _activeCount++;
    _inFlightRequests[request.file.fileId] = request;
    _executeRequest(request);
  }

  /// Executes disk check and Telegram background download for a single thumbnail request.
  Future<void> _executeRequest(_ThumbnailRequest request) async {
    final file = request.file;
    final reqPriority = request.isPriority
        ? RequestPriority.immediate
        : RequestPriority.background;

    try {
      if (!kIsWeb) {
        // Native fast disk check
        final cachedPath =
            await ThumbnailHelper.cachedThumbnailPath(file.fileId);

        if (request.isCancelled) return;

        if (cachedPath != null) {
          try {
            final fileObj = File(cachedPath);
            if (await fileObj.exists()) {
              final bytes = await fileObj.readAsBytes();
              addToMemoryCache(file.fileId, bytes);
              if (!request.completer.isCompleted) {
                request.completer.complete(bytes);
              }
              return;
            }
          } catch (_) {}
          if (!request.completer.isCompleted) {
            request.completer.complete(cachedPath);
          }
          return;
        }
      }

      if (request.isCancelled) return;

      final bytes = await _telegram.downloadByFileId(
        file.thumbnailFileId!,
        reqPriority,
      );

      if (request.isCancelled) return;

      addToMemoryCache(file.fileId, bytes);

      if (!kIsWeb) {
        try {
          await ThumbnailHelper.cacheThumbnail(file.fileId, bytes);
        } catch (_) {}
      }

      if (!request.completer.isCompleted) {
        request.completer.complete(bytes);
      }
    } catch (e) {
      AppLogger.e('Failed to load thumbnail for ${file.fileId}: $e',
          tag: 'ThumbnailRepository');
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
    } finally {
      _activeCount--;
      _inFlightRequests.remove(file.fileId);
      _activeDownloads.remove(file.fileId);
      _pumpQueue();
    }
  }
}

