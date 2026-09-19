/*
 * File: raw_stream_web.dart
 * Description: Web platform stub for disk-based raw stream chunking operations.
 */

import 'dart:typed_data';

/// Throws UnsupportedError because filesystem paths are unavailable on web.
Future<({String sha256, int fileSize})> hashFilePath(
  String path, {
  void Function(double progress)? onProgress,
}) async {
  throw UnsupportedError(
      'Disk file path streaming is not supported on web platforms.');
}

/// Throws UnsupportedError because filesystem paths are unavailable on web.
Future<Uint8List> readDiskSlice(
  String path,
  int offset,
  int length,
) async {
  throw UnsupportedError(
      'Disk file path reading is not supported on web platforms.');
}
