/*
 * File: thumbnail_repository.dart
 * Description: Two-tiered LRU memory and disk thumbnail repository providing synchronous zero-latency memory cache hits and background network/disk deduplication.
 */

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

/// Central repository managing high-speed LRU memory and disk cached media thumbnails.
class ThumbnailRepository {
  final TelegramService _telegram;
  final Map<String, Future<dynamic>> _activeDownloads = {};

  /// Maximum number of thumbnail payloads kept in high-speed RAM (~6-8 MB total).
  static const int maxMemoryCacheSize = 200;

  /// High-speed LRU memory cache storing binary thumbnail bytes for zero-latency scroll rendering.
  final LinkedHashMap<String, Uint8List> _memoryCache = LinkedHashMap();

  /// Constructs ThumbnailRepository.
  ThumbnailRepository(this._telegram);

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

  /// Clears the entire memory cache.
  void clearMemoryCache() {
    _memoryCache.clear();
    _activeDownloads.clear();
  }

  /// Evicts a thumbnail from memory and deletes its cached disk files.
  Future<void> evict(String fileId) async {
    _memoryCache.remove(fileId);
    _activeDownloads.remove(fileId);
    await ThumbnailHelper.deleteCachedThumbnail(fileId);
  }

  /// Current number of items in memory cache.
  int get memoryCacheCount => _memoryCache.length;

  /// Retrieves thumbnail data (memory bytes on fast-hit, cached disk path on native), downloading if necessary.
  Future<dynamic> getThumbnailData(FileRecord file, {bool isPriority = false}) async {
    if (file.thumbnailFileId == null) return null;

    final reqPriority =
        isPriority ? RequestPriority.immediate : RequestPriority.normal;

    // 1. Fast path: Check synchronous in-memory LRU cache
    final memHit = getMemoryCachedBytes(file.fileId);
    if (memHit != null) return memHit;

    // 2. Check active in-flight download to avoid duplicate network requests
    if (_activeDownloads.containsKey(file.fileId)) {
      return _activeDownloads[file.fileId];
    }

    if (kIsWeb) {
      final downloadFuture = () async {
        try {
          final bytes =
              await _telegram.downloadByFileId(file.thumbnailFileId!, reqPriority);
          addToMemoryCache(file.fileId, bytes);
          return bytes;
        } catch (e) {
          AppLogger.e('Failed to download web thumbnail: $e',
              tag: 'ThumbnailRepository');
          return null;
        } finally {
          _activeDownloads.remove(file.fileId);
        }
      }();

      _activeDownloads[file.fileId] = downloadFuture;
      return downloadFuture;
    } else {
      // Native fast disk check
      final cachedPath = await ThumbnailHelper.cachedThumbnailPath(file.fileId);
      if (cachedPath != null) {
        // Asynchronously populate memory cache for subsequent instant hits
        try {
          final fileObj = File(cachedPath);
          if (await fileObj.exists()) {
            final bytes = await fileObj.readAsBytes();
            addToMemoryCache(file.fileId, bytes);
            return bytes;
          }
        } catch (_) {}
        return cachedPath;
      }

      final downloadFuture = () async {
        try {
          final bytes = await _telegram.downloadByFileId(file.thumbnailFileId!);
          addToMemoryCache(file.fileId, bytes);
          await ThumbnailHelper.cacheThumbnail(file.fileId, bytes);
          return bytes;
        } catch (e) {
          AppLogger.e('Failed to download native thumbnail: $e',
              tag: 'ThumbnailRepository');
          return null;
        } finally {
          _activeDownloads.remove(file.fileId);
        }
      }();

      _activeDownloads[file.fileId] = downloadFuture;
      return downloadFuture;
    }
  }
}
