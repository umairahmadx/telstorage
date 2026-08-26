/*
 * File: chunk_resume_service.dart
 * Description: Manages persistent chunk state and thumbnail references in Hive for crash-resilient upload resumption.
 */

import 'package:hive/hive.dart';
import '../constants/app_constants.dart';
import '../models/chunk_info.dart';

/// Service managing disk-persisted chunk upload progress for instant crash resumption.
class ChunkResumeService {
  ChunkResumeService._();

  /// Singleton instance of ChunkResumeService.
  static final ChunkResumeService instance = ChunkResumeService._();

  Box? get _box => Hive.isBoxOpen(AppConstants.uploadChunksBox)
      ? Hive.box(AppConstants.uploadChunksBox)
      : null;

  /// Retrieves already uploaded chunks for [hash].
  Map<int, ChunkInfo> getUploadedChunks(String hash) {
    final raw = _box?.get('chunks_$hash') as Map<dynamic, dynamic>?;
    final map = <int, ChunkInfo>{};
    if (raw != null) {
      raw.forEach((k, v) {
        if (v is Map) {
          try {
            final chunk = ChunkInfo.fromJson(Map<String, dynamic>.from(v));
            map[chunk.index] = chunk;
          } catch (_) {}
        }
      });
    }
    return map;
  }

  /// Persists a successfully uploaded chunk.
  Future<void> saveUploadedChunk(String hash, int index, ChunkInfo info) async {
    final box = _box;
    if (box == null) return;
    final key = 'chunks_$hash';
    final existing = Map<dynamic, dynamic>.from(box.get(key) as Map? ?? {});
    existing[index] = info.toJson();
    await box.put(key, existing);
  }

  /// Retrieves cached thumbnail file ID if already uploaded before an interruption.
  String? getCachedThumbnailFileId(String hash) =>
      _box?.get('thumb_$hash') as String?;

  /// Caches uploaded thumbnail file ID.
  Future<void> saveThumbnailFileId(String hash, String fileId) async =>
      await _box?.put('thumb_$hash', fileId);

  /// Purges cached chunk and thumbnail records on successful file completion.
  Future<void> clearFileCache(String hash) async {
    final box = _box;
    if (box != null) {
      await box.delete('chunks_$hash');
      await box.delete('thumb_$hash');
    }
  }
}
