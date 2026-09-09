/*
 * File: video_chunk_cache_manager.dart
 * Description: Dedicated LRU disk cache manager for 19 MB video streaming chunks with atomic persistence.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import '../utils/app_logger.dart';

/// Singleton manager responsible for caching, atomic writing, and LRU pruning
/// of partitioned video chunks on local disk.
class VideoChunkCacheManager {
  VideoChunkCacheManager._();

  /// Singleton instance of VideoChunkCacheManager.
  static final VideoChunkCacheManager instance = VideoChunkCacheManager._();

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
    final tmpFile = File('${dir.path}/chunk_$chunkIndex.part.tmp');

    if (tmpFile.existsSync()) {
      tmpFile.deleteSync();
    }

    await tmpFile.writeAsBytes(bytes, flush: true);
    final renamed = await tmpFile.rename(targetFile.path);
    try {
      renamed.setLastModifiedSync(DateTime.now());
    } catch (_) {}
    return renamed;
  }

  /// Checks if a fully assembled uncompressed video file exists in the cache.
  Future<File?> getLocalFullVideo(String fileId) async {
    if (kIsWeb) return null;
    try {
      final dir = await getChunkDir(fileId);
      final fullFile = File('${dir.path}/full_video.mp4');
      if (fullFile.existsSync() && fullFile.lengthSync() > 0) {
        try {
          fullFile.setLastModifiedSync(DateTime.now());
        } catch (_) {}
        return fullFile;
      }
    } catch (e) {
      AppLogger.w('Failed to check local full video: $e', tag: 'VideoChunkCacheManager');
    }
    return null;
  }

  /// Atomically saves fully assembled video bytes to disk.
  Future<File> saveFullVideo(String fileId, Uint8List bytes) async {
    final dir = await getChunkDir(fileId);
    final targetFile = File('${dir.path}/full_video.mp4');
    final tmpFile = File('${dir.path}/full_video.mp4.tmp');

    if (tmpFile.existsSync()) {
      tmpFile.deleteSync();
    }

    await tmpFile.writeAsBytes(bytes, flush: true);
    final renamed = await tmpFile.rename(targetFile.path);
    try {
      renamed.setLastModifiedSync(DateTime.now());
    } catch (_) {}
    return renamed;
  }

  /// Reassembles partitioned chunks, decompresses legacy DEFLATE archives,
  /// and saves the resulting raw uncompressed video to local disk.
  Future<File> assembleAndDecompressLegacyZip(
    String fileId,
    List<Uint8List> chunks,
  ) async {
    final builder = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      builder.add(chunk);
    }
    final assembled = builder.toBytes();
    final archive = ZipDecoder().decodeBytes(assembled);
    if (archive.isEmpty) {
      throw Exception('Legacy ZIP archive for $fileId was empty');
    }
    final rawBytes = archive.first.content;
    return await saveFullVideo(fileId, rawBytes);
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

  /// Enforces LRU pruning if total video cache exceeds [maxSizeBytes] (default 250 MB).
  Future<void> evictOldestIfNeeded({int maxSizeBytes = 250 * 1024 * 1024}) async {
    if (kIsWeb) return;

    try {
      final base = await getBaseDir();
      if (!base.existsSync()) return;

      final partFiles = <File>[];
      int currentTotal = 0;

      for (final entity in base.listSync(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.part')) {
          partFiles.add(entity);
          currentTotal += entity.lengthSync();
        }
      }

      if (currentTotal <= maxSizeBytes) return;

      // Sort oldest accessed first
      partFiles.sort((a, b) {
        final aMod = a.lastModifiedSync();
        final bMod = b.lastModifiedSync();
        return aMod.compareTo(bMod);
      });

      for (final file in partFiles) {
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
