/*
 * File: zip_stream_web.dart
 * Description: Web stub for disk-based zip streaming operations.
 */

import 'dart:typed_data';

/// Throws UnsupportedError because file paths are unavailable on web.
Future<({String sha256, int crc32, int fileSize})> hashAndCrcPath(
  String path, {
  void Function(double progress)? onProgress,
}) async {
  throw UnsupportedError(
      'Disk file path streaming is not supported on web platforms.');
}

/// Throws UnsupportedError because file paths are unavailable on web.
Future<Uint8List> readDiskSlice(
  String path,
  int offset,
  int length,
) async {
  throw UnsupportedError(
      'Disk file path reading is not supported on web platforms.');
}
