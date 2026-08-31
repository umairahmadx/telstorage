/*
 * File: upload_task.dart
 * Description: Model definition for UploadTask representing queued and in-flight upload items with pre-processing metadata.
 */

import 'dart:typed_data';
import '../../../../core/utils/file_reader_stub.dart'
    if (dart.library.io) '../../../../core/utils/file_reader_native.dart';

/// Immutable description of a queued upload payload with pre-processing metadata.
class UploadTask {
  final String id;
  final Uint8List? bytes;
  final String? path;
  final String name;
  final int? size;
  final String? folderId;
  final bool isTemporaryCacheFile;
  String? precomputedHash;
  Uint8List? precomputedThumbnailBytes;
  String? thumbnailExtension;

  UploadTask({
    required this.id,
    this.bytes,
    this.path,
    required this.name,
    this.size,
    this.folderId,
    this.isTemporaryCacheFile = false,
    this.precomputedHash,
    this.precomputedThumbnailBytes,
    this.thumbnailExtension,
  }) : assert(bytes != null || path != null,
            'UploadTask must have either in-memory bytes or a filesystem path.');

  /// Reads bytes on-demand for execution, releasing immediately after upload.
  Future<Uint8List> getBytes() async {
    if (bytes != null) return bytes!;
    if (path != null) return await readFileBytes(path!);
    throw StateError('UploadTask has neither bytes nor valid path.');
  }

  /// Deletes the temporary cache file if marked as temporary.
  Future<void> cleanupCacheFile() async {
    if (isTemporaryCacheFile && path != null) {
      await deleteFileIfExists(path!);
    }
  }
}
