/*
 * File: app_cache_manager.dart
 * Description: Central cache manager computing multi-partition disk sizes, managing user-defined limits, and executing LRU evictions.
 */

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_logger.dart';
import 'lru_folder_cache_service.dart';

/// Data model representing storage utilization across segregated cache partitions.
class CachePartitionStats {
  /// Thumbnail disk cache size in bytes.
  final int thumbnailBytes;

  /// Count of cached thumbnail files.
  final int thumbnailCount;

  /// Local database & partition metadata size in bytes.
  final int databaseBytes;

  /// Temporary chunk and transfer cache in bytes.
  final int tempBytes;

  /// User-configured total cache limit in megabytes.
  final int limitMb;

  /// Constructs CachePartitionStats.
  const CachePartitionStats({
    required this.thumbnailBytes,
    required this.thumbnailCount,
    required this.databaseBytes,
    required this.tempBytes,
    required this.limitMb,
  });

  /// Total combined cache size in bytes.
  int get totalBytes => thumbnailBytes + databaseBytes + tempBytes;

  /// Total combined cache size in megabytes.
  double get totalMb => totalBytes / (1024 * 1024);

  /// Formatted total cache string (e.g. "24.5 MB").
  String get formattedTotal => _formatBytes(totalBytes);

  /// Formatted thumbnail cache string.
  String get formattedThumbnails => _formatBytes(thumbnailBytes);

  /// Formatted database cache string.
  String get formattedDatabase => _formatBytes(databaseBytes);

  /// Formatted temp cache string.
  String get formattedTemp => _formatBytes(tempBytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Central controller managing disk partitions, LRU evictions, and user cache budgets.
class AppCacheManager {
  AppCacheManager._();

  /// Singleton instance of AppCacheManager.
  static final AppCacheManager instance = AppCacheManager._();

  static const String _prefCacheLimitKey = 'app_cache_limit_mb';

  /// Default cache ceiling in megabytes (250 MB).
  static const int defaultCacheLimitMb = 250;

  /// Available selectable cache limit steps in megabytes.
  static const List<int> supportedLimitsMb = [50, 100, 250, 500, 1024, 2048];

  /// Loads current user cache limit setting in megabytes.
  Future<int> getCacheLimitMb() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_prefCacheLimitKey) ?? defaultCacheLimitMb;
    } catch (_) {
      return defaultCacheLimitMb;
    }
  }

  /// Sets user cache limit and runs LRU eviction if current cache exceeds budget.
  Future<void> setCacheLimitMb(int limitMb) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefCacheLimitKey, limitMb);
      AppLogger.i('Cache limit updated to $limitMb MB', tag: 'AppCacheManager');
      await enforceCacheLimit(limitMb);
    } catch (e) {
      AppLogger.w('Failed to set cache limit: $e', tag: 'AppCacheManager');
    }
  }

  /// Computes live storage sizes across all segregated cache partitions.
  Future<CachePartitionStats> getPartitionStats() async {
    if (kIsWeb) {
      final limitMb = await getCacheLimitMb();
      return CachePartitionStats(
        thumbnailBytes: 0,
        thumbnailCount: 0,
        databaseBytes: 0,
        tempBytes: 0,
        limitMb: limitMb,
      );
    }

    try {
      final limitMb = await getCacheLimitMb();
      final tempDir = await getTemporaryDirectory();
      final appDocDir = await getApplicationDocumentsDirectory();

      // 1. Thumbnail Partition
      int thumbBytes = 0;
      int thumbCount = 0;
      final thumbDir = Directory('${tempDir.path}/thumbnails');
      final videoThumbDir = Directory('${tempDir.path}/video_thumbs');

      if (thumbDir.existsSync()) {
        for (final file in thumbDir.listSync(followLinks: false)) {
          if (file is File) {
            thumbBytes += file.lengthSync();
            thumbCount++;
          }
        }
      }
      if (videoThumbDir.existsSync()) {
        for (final file in videoThumbDir.listSync(followLinks: false)) {
          if (file is File) {
            thumbBytes += file.lengthSync();
            thumbCount++;
          }
        }
      }

      // 2. Database & Folder Partition Cache
      int dbBytes = 0;
      if (appDocDir.existsSync()) {
        for (final file in appDocDir.listSync(followLinks: false)) {
          if (file is File &&
              (file.path.endsWith('.hive') ||
                  file.path.endsWith('.lock') ||
                  file.path.contains('partition'))) {
            dbBytes += file.lengthSync();
          }
        }
      }

      // 3. Temporary / Transfer Chunk Cache
      int tempBytes = 0;
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync(followLinks: false)) {
          if (entity is File &&
              !entity.path.contains('thumbnails') &&
              !entity.path.contains('video_thumbs')) {
            tempBytes += entity.lengthSync();
          }
        }
      }

      return CachePartitionStats(
        thumbnailBytes: thumbBytes,
        thumbnailCount: thumbCount,
        databaseBytes: dbBytes,
        tempBytes: tempBytes,
        limitMb: limitMb,
      );
    } catch (e) {
      AppLogger.w('Failed to compute partition stats: $e', tag: 'AppCacheManager');
      final limitMb = await getCacheLimitMb();
      return CachePartitionStats(
        thumbnailBytes: 0,
        thumbnailCount: 0,
        databaseBytes: 0,
        tempBytes: 0,
        limitMb: limitMb,
      );
    }
  }

  /// Clears only the media thumbnail cache partition.
  Future<void> clearThumbnailCache() async {
    if (kIsWeb) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final thumbDir = Directory('${tempDir.path}/thumbnails');
      final videoThumbDir = Directory('${tempDir.path}/video_thumbs');

      if (thumbDir.existsSync()) thumbDir.deleteSync(recursive: true);
      if (videoThumbDir.existsSync()) videoThumbDir.deleteSync(recursive: true);

      AppLogger.i('Thumbnail cache partition cleared', tag: 'AppCacheManager');
    } catch (e) {
      AppLogger.e('Error clearing thumbnail cache: $e', tag: 'AppCacheManager');
    }
  }

  /// Clears in-flight chunk downloads and temp transfer files.
  Future<void> clearTempCache() async {
    if (kIsWeb) return;
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync(followLinks: false)) {
          if (entity is File &&
              !entity.path.contains('thumbnails') &&
              !entity.path.contains('video_thumbs')) {
            entity.deleteSync();
          }
        }
      }
      AppLogger.i('Temporary chunk cache cleared', tag: 'AppCacheManager');
    } catch (e) {
      AppLogger.e('Error clearing temp cache: $e', tag: 'AppCacheManager');
    }
  }

  /// Clears in-memory LRU folder partitions.
  Future<void> clearFolderPartitionCache() async {
    LruFolderCacheService.instance.clear();
    AppLogger.i('Folder partition memory cache cleared', tag: 'AppCacheManager');
  }

  /// Clears all segregated local caches.
  Future<void> clearAllCache() async {
    await clearThumbnailCache();
    await clearTempCache();
    await clearFolderPartitionCache();
    AppLogger.i('All local cache partitions successfully flushed', tag: 'AppCacheManager');
  }

  /// Enforces user-configured cache ceiling using LRU eviction on oldest thumbnail files.
  Future<void> enforceCacheLimit([int? overrideLimitMb]) async {
    if (kIsWeb) return;
    try {
      final limitMb = overrideLimitMb ?? await getCacheLimitMb();
      final maxBytes = limitMb * 1024 * 1024;
      final stats = await getPartitionStats();

      if (stats.totalBytes <= maxBytes) return;

      AppLogger.i(
        'Cache size (${stats.formattedTotal}) exceeds limit ($limitMb MB). Running LRU eviction...',
        tag: 'AppCacheManager',
      );

      final tempDir = await getTemporaryDirectory();
      final thumbDir = Directory('${tempDir.path}/thumbnails');

      if (thumbDir.existsSync()) {
        final files = thumbDir
            .listSync()
            .whereType<File>()
            .toList()
          ..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

        int freedBytes = 0;
        final targetBytesToFree = stats.totalBytes - (maxBytes * 0.85).toInt();

        for (final file in files) {
          if (freedBytes >= targetBytesToFree) break;
          try {
            final len = file.lengthSync();
            file.deleteSync();
            freedBytes += len;
          } catch (_) {}
        }
        AppLogger.i('LRU eviction freed ${(freedBytes / 1024).toStringAsFixed(1)} KB',
            tag: 'AppCacheManager');
      }
    } catch (e) {
      AppLogger.w('enforceCacheLimit warning: $e', tag: 'AppCacheManager');
    }
  }
}
