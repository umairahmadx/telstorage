/*
 * File: download_disk_writer_web.dart
 * Description: Web platform stub for DownloadDiskWriter.
 */

import 'dart:typed_data';
import 'native_save_stub.dart';

/// Web stub for DownloadDiskWriter (delegates to in-memory browser downloads on web).
class DownloadDiskWriter {
  DownloadDiskWriter._();

  static Future<DownloadDiskWriter> create({
    required String filename,
    String? subpath,
    DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
    String? explicitTargetPath,
  }) async {
    throw UnsupportedError('DownloadDiskWriter is not supported on web.');
  }

  Future<void> appendChunk(Uint8List chunkBytes) async {
    throw UnsupportedError('DownloadDiskWriter is not supported on web.');
  }

  Future<NativeSaveResult> closeAndFinalize(String expectedHash) async {
    throw UnsupportedError('DownloadDiskWriter is not supported on web.');
  }

  Future<void> abort() async {}
}
