/*
 * File: zip_stream_native.dart
 * Description: Native platform implementation for disk-based zip streaming and hash computation.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

/// Computes SHA-256 and CRC-32 for a file on disk in streaming chunks without loading file into RAM.
Future<({String sha256, int crc32, int fileSize})> hashAndCrcPath(
  String path, {
  void Function(double progress)? onProgress,
}) async {
  final file = File(path);
  if (!await file.exists()) {
    throw PathNotFoundException(
      path,
      const OSError('File does not exist or was removed', 2),
    );
  }

  final totalSize = await file.length();
  final output = AccumulatorSink<Digest>();
  final input = sha256.startChunkedConversion(output);

  int crc = 0;
  int bytesProcessed = 0;

  final stream = file.openRead();
  await for (final chunk in stream) {
    input.add(chunk);
    crc = getCrc32(chunk, crc);
    bytesProcessed += chunk.length;
    if (totalSize > 0 && onProgress != null) {
      onProgress(bytesProcessed / totalSize);
    }
  }
  input.close();

  return (
    sha256: output.events.single.toString(),
    crc32: crc,
    fileSize: totalSize,
  );
}

/// Reads a specific slice of bytes directly from disk without reading the full file.
Future<Uint8List> readDiskSlice(
  String path,
  int offset,
  int length,
) async {
  if (length <= 0) return Uint8List(0);
  final file = File(path);
  final raf = await file.open(mode: FileMode.read);
  try {
    await raf.setPosition(offset);
    return await raf.read(length);
  } finally {
    await raf.close();
  }
}
