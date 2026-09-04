/*
 * File: image_viewer_cache_service.dart
 * Description: High-performance LRU image cache service managing full-resolution previews, deduplication, and prefetching.
 */

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import '../utils/thumbnail_helper_native.dart'
    if (dart.library.js_interop) '../utils/thumbnail_helper_web.dart';
import 'app_cache_manager.dart';
import 'service_locator.dart';
import 'telegram_rate_limiter.dart';

/// Singleton service responsible for caching full-resolution images for the in-app viewer.
class ImageViewerCacheService {
  ImageViewerCacheService._();

  /// Singleton instance of ImageViewerCacheService.
  static final ImageViewerCacheService instance = ImageViewerCacheService._();

  /// In-flight download futures deduplication map.
  final Map<String, Future<File?>> _inFlightDownloads = {};

  /// Validates whether a given FileRecord represents a viewable image.
  static bool isImageRecord(FileRecord file) {
    final mime = file.mimeType.toLowerCase();
    if (mime.startsWith('image/')) return true;
    final name = file.name.toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif') ||
        name.endsWith('.bmp') ||
        name.endsWith('.heic');
  }

  /// Resolves the dedicated local cache file path for an image.
  Future<File> getCacheTargetFile(FileRecord file) async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/image_cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final ext = p.extension(file.name);
    final safeExt = ext.isNotEmpty ? ext : '.jpg';
    return File('${cacheDir.path}/${file.fileId}$safeExt');
  }

  /// Checks if a full-resolution image is already cached on disk or downloaded.
  /// If cached, touches its access time to maintain true LRU recency.
  Future<File?> getCachedImageFile(FileRecord file) async {
    if (kIsWeb) return null;

    try {
      final cacheFile = await getCacheTargetFile(file);
      if (cacheFile.existsSync()) {
        try {
          cacheFile.setLastModifiedSync(DateTime.now());
        } catch (_) {}
        return cacheFile;
      }

      // Check permanent completed downloads partition
      if (ServiceLocator.instance.isInitialized) {
        final completedPath =
            ServiceLocator.instance.downloadQueue.getCompletedPath(file.fileId);
        if (completedPath != null) {
          final completedFile = File(completedPath);
          if (completedFile.existsSync()) {
            return completedFile;
          }
        }
      }
    } catch (e) {
      AppLogger.w('Error checking cached image file: $e',
          tag: 'ImageViewerCacheService');
    }

    return null;
  }

  /// Asynchronously downloads the full-resolution image and caches it on disk.
  Future<File?> downloadImageToCache(
    FileRecord file, {
    bool isPriority = false,
    void Function(double progress, String status)? onProgress,
  }) async {
    if (kIsWeb) return null;

    // Check existing cache hit
    final existing = await getCachedImageFile(file);
    if (existing != null) {
      onProgress?.call(1.0, 'Ready');
      return existing;
    }

    // Deduplicate concurrent in-flight download requests
    if (_inFlightDownloads.containsKey(file.fileId)) {
      return _inFlightDownloads[file.fileId]!;
    }

    final downloadFuture = () async {
      try {
        onProgress?.call(0.05, 'Starting…');
        final bytes = await ServiceLocator.instance.downloadService
            .downloadFile(
          file,
          (pct, status) {
            onProgress?.call(pct, status);
          },
          priority: isPriority
              ? RequestPriority.immediate
              : RequestPriority.background,
        );

        final targetFile = await getCacheTargetFile(file);
        final tempStaging = File('${targetFile.path}.tmp');
        await tempStaging.writeAsBytes(bytes, flush: true);

        if (targetFile.existsSync()) {
          try {
            targetFile.deleteSync();
          } catch (_) {}
        }
        await tempStaging.rename(targetFile.path);

        try {
          targetFile.setLastModifiedSync(DateTime.now());
        } catch (_) {}

        // Enforce user-defined cache budget in the background
        AppCacheManager.instance.enforceCacheLimit();

        AppLogger.i('Cached full image ${file.name} (${targetFile.lengthSync()} bytes)',
            tag: 'ImageViewerCacheService');
        return targetFile;
      } catch (e) {
        AppLogger.w('Failed to download image to cache: $e',
            tag: 'ImageViewerCacheService');
        return null;
      } finally {
        _inFlightDownloads.remove(file.fileId);
      }
    }();

    _inFlightDownloads[file.fileId] = downloadFuture;
    return downloadFuture;
  }

  /// Prefetches an adjacent image in the folder with low-priority background execution.
  void prefetchImage(FileRecord file) {
    if (kIsWeb || !isImageRecord(file)) return;
    getCachedImageFile(file).then((existing) {
      if (existing == null && !_inFlightDownloads.containsKey(file.fileId)) {
        downloadImageToCache(file, isPriority: false).catchError((_) => null);
      }
    });
  }

  /// Shares the image directly to another application as an image binary (not a link).
  Future<void> shareImage(FileRecord file, BuildContext context) async {
    try {
      final cachedFile = await getCachedImageFile(file);
      if (cachedFile != null) {
        await SharePlus.instance.share(ShareParams(
          files: [XFile(cachedFile.path)],
          text: file.name,
        ));
        return;
      }

      // If full file is not cached yet, check if thumbnail file is available
      final thumbPath = await ThumbnailHelper.cachedThumbnailPath(file.fileId);
      if (thumbPath != null && File(thumbPath).existsSync()) {
        await SharePlus.instance.share(ShareParams(
          files: [XFile(thumbPath)],
          text: file.name,
        ));
        return;
      }

      // Otherwise download to cache first then share
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloading image to share…'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      final downloaded = await downloadImageToCache(file, isPriority: true);
      if (downloaded != null) {
        await SharePlus.instance.share(ShareParams(
          files: [XFile(downloaded.path)],
          text: file.name,
        ));
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to download image for sharing.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      AppLogger.e('Error sharing image binary: $e',
          tag: 'ImageViewerCacheService');
    }
  }

  /// Saves the cached image permanently to user device Downloads or Pictures folder.
  Future<bool> saveToDevice(FileRecord file, BuildContext context) async {
    try {
      File? sourceFile = await getCachedImageFile(file);
      sourceFile ??= await downloadImageToCache(file, isPriority: true);

      if (sourceFile == null || !sourceFile.existsSync()) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to retrieve image for saving.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }

      final bytes = await sourceFile.readAsBytes();
      final result = await ServiceLocator.instance.downloadService
          .saveAndOpen(bytes, file.name);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return result.success;
    } catch (e) {
      AppLogger.e('Error saving image to device: $e',
          tag: 'ImageViewerCacheService');
      return false;
    }
  }
}
