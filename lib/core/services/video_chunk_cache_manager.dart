/*
 * File: video_chunk_cache_manager.dart
 * Description: Dedicated LRU disk cache manager for 19 MB video streaming chunks with atomic persistence.
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, ValueNotifier;
import 'package:path_provider/path_provider.dart';
import '../utils/app_logger.dart';

/// Singleton manager responsible for caching, atomic writing, and LRU pruning
/// of partitioned video chunks on local disk.
class VideoChunkCacheManager {
  VideoChunkCacheManager._();

  /// Singleton instance of VideoChunkCacheManager.
  static final VideoChunkCacheManager instance = VideoChunkCacheManager._();

  /// Listenable notifier bumped whenever a new video chunk is written to disk.
  final ValueNotifier<int> chunkChangeNotifier = ValueNotifier(0);

  Directory? _baseDirForTesting;

  /// Sets an isolated directory for unit testing.
  void setBaseDirForTesting(Directory? dir) {
    _baseDirForTesting = dir;
  }

  /// Resolves the root directory where video chunks are segregated.
  Future<Directory> getBaseDir() async {
    final Directory base;
    if (_baseDirForTesting != null) {
      base = Directory('${_baseDirForTesting!.path}/video_chunks');
    } else {
      final tempDir = await getTemporaryDirectory();
      base = Directory('${tempDir.path}/video_chunks');
    }

    if (!base.existsSync()) {
      base.createSync(recursive: true);
    }
    return base;
  }

  /// Generates a filesystem-safe folder name for any arbitrary opaque fileId.
  static String sanitizeFileId(String fileId) {
    return fileId.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  /// Resolves the dedicated subfolder for a specific video file's chunks.
  Future<Directory> getChunkDir(String fileId) async {
    final base = await getBaseDir();
    final safeId = sanitizeFileId(fileId);
    final chunkDir = Directory('${base.path}/$safeId');
    if (!chunkDir.existsSync()) {
      chunkDir.createSync(recursive: true);
    }
    return chunkDir;
  }

  /// Checks if a given 19 MB chunk is already cached on disk.
  /// If found, touches its last-modified timestamp for LRU recency tracking.
  Future<File?> getCachedChunk(String fileId, int chunkIndex) async {
    if (kIsWeb) return null;

    try {
      final dir = await getChunkDir(fileId);
      final chunkFile = File('${dir.path}/chunk_$chunkIndex.part');
      if (chunkFile.existsSync()) {
        try {
          chunkFile.setLastModifiedSync(DateTime.now());
        } catch (_) {}
        return chunkFile;
      }
    } catch (e) {
      AppLogger.w('Failed to get cached chunk: $e', tag: 'VideoChunkCacheManager');
    }
    return null;
  }

  /// Saves [bytes] for a given chunk index using an atomic write-then-rename strategy.
  Future<File> saveChunk(String fileId, int chunkIndex, Uint8List bytes) async {
    final dir = await getChunkDir(fileId);
    final targetFile = File('${dir.path}/chunk_$chunkIndex.part');
    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      return targetFile;
    }

    final uniqueSuffix = '${DateTime.now().microsecondsSinceEpoch}_$chunkIndex';
    final tmpFile = File('${dir.path}/chunk_${chunkIndex}_$uniqueSuffix.part.tmp');

    await tmpFile.writeAsBytes(bytes, flush: true);
    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      try {
        tmpFile.deleteSync();
      } catch (_) {}
      return targetFile;
    }
    final renamed = await tmpFile.rename(targetFile.path);
    try {
      renamed.setLastModifiedSync(DateTime.now());
    } catch (_) {}

    chunkChangeNotifier.value++;

    // Trigger priority eviction in background so cache ceiling is always respected.
    unawaited(evictOldestIfNeeded(activeFileId: fileId));

    return renamed;
  }

  /// Returns the set of chunk indices (0-based) currently persisted in the cache directory for [fileId].
  Future<Set<int>> getCachedChunkIndices(String fileId) async {
    if (kIsWeb) return const {};
    try {
      final dir = await getChunkDir(fileId);
      if (!dir.existsSync()) return const {};
      final indices = <int>{};
      for (final entity in dir.listSync(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.part')) {
          final filename = entity.uri.pathSegments.last;
          final match = RegExp(r'^chunk_(\d+)\.part$').firstMatch(filename);
          if (match != null) {
            indices.add(int.parse(match.group(1)!));
          }
        }
      }
      return indices;
    } catch (e) {
      AppLogger.w('Failed to list cached chunk indices for $fileId: $e',
          tag: 'VideoChunkCacheManager');
      return const {};
    }
  }

  /// Clears chunks for a specific [fileId], or all video chunks if [fileId] is null.
  Future<void> clearVideoCache({String? fileId}) async {
    if (kIsWeb) return;

    try {
      final base = await getBaseDir();
      if (!base.existsSync()) return;

      if (fileId != null) {
        final safeId = sanitizeFileId(fileId);
        final dir = Directory('${base.path}/$safeId');
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      } else {
        for (final entity in base.listSync(followLinks: false)) {
          if (entity.existsSync()) {
            entity.deleteSync(recursive: true);
          }
        }
      }
      AppLogger.i('Video cache cleared${fileId != null ? " for $fileId" : ""}',
          tag: 'VideoChunkCacheManager');
    } catch (e) {
      AppLogger.e('Error clearing video cache: $e', tag: 'VideoChunkCacheManager');
    }
  }

  /// Computes the total byte footprint across all cached video chunks.
  Future<int> getTotalVideoCacheBytes() async {
    if (kIsWeb) return 0;

    try {
      final base = await getBaseDir();
      if (!base.existsSync()) return 0;

      int total = 0;
      for (final entity in base.listSync(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.part')) {
          total += entity.lengthSync();
        }
      }
      return total;
    } catch (e) {
      AppLogger.w('Error computing video cache bytes: $e',
          tag: 'VideoChunkCacheManager');
      return 0;
    }
  }

  /// Enforces two-tier LRU pruning if total video cache exceeds [maxSizeBytes] (default 250 MB).
  ///
  /// Eviction Priority:
  /// - Tier 1: Chunks from other/previous videos (fileId != [activeFileId]), sorted oldest first.
  /// - Tier 2: Chunks from the currently active video (fileId == [activeFileId]), sorted oldest first.
  Future<void> evictOldestIfNeeded({
    int maxSizeBytes = 250 * 1024 * 1024,
    String? activeFileId,
  }) async {
    if (kIsWeb) return;

    try {
      final base = await getBaseDir();
      if (!base.existsSync()) return;

      final otherVideoChunks = <File>[];
      final activeVideoChunks = <File>[];
      int currentTotal = 0;
      final safeActiveId = activeFileId != null ? sanitizeFileId(activeFileId) : null;

      for (final entity in base.listSync(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.part')) {
          currentTotal += entity.lengthSync();
          final parentDirName = entity.parent.path.split(RegExp(r'[\\/]')).last;
          if (safeActiveId != null && parentDirName == safeActiveId) {
            activeVideoChunks.add(entity);
          } else {
            otherVideoChunks.add(entity);
          }
        }
      }

      if (currentTotal <= maxSizeBytes) return;

      int sortByAge(File a, File b) {
        final aMod = a.lastModifiedSync();
        final bMod = b.lastModifiedSync();
        return aMod.compareTo(bMod);
      }

      otherVideoChunks.sort(sortByAge);
      activeVideoChunks.sort(sortByAge);

      // Tier 1: Delete all other videos' chunks first
      // Tier 2: Delete active video's oldest chunks only if still over limit
      final evictionCandidates = [...otherVideoChunks, ...activeVideoChunks];

      for (final file in evictionCandidates) {
        if (currentTotal <= maxSizeBytes) break;
        final size = file.lengthSync();
        try {
          file.deleteSync();
          currentTotal -= size;
        } catch (_) {}
      }

      // Cleanup empty file folders
      for (final entity in base.listSync(followLinks: false)) {
        if (entity is Directory && entity.listSync().isEmpty) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (e) {
      AppLogger.e('Error evicting video cache: $e', tag: 'VideoChunkCacheManager');
    }
  }
}
