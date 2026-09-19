/*
 * File: raw_stream_native.dart
 * Description: Native platform implementation for disk-based raw stream chunking and SHA-256 computation.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

/// Computes SHA-256 for a file on disk in streaming chunks without loading the entire file into RAM.
Future<({String sha256, int fileSize})> hashFilePath(
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

  int bytesProcessed = 0;

  final stream = file.openRead();
  await for (final chunk in stream) {
    input.add(chunk);
    bytesProcessed += chunk.length;
    if (totalSize > 0 && onProgress != null) {
      onProgress(bytesProcessed / totalSize);
    }
  }
  input.close();

  return (
    sha256: output.events.single.toString(),
    fileSize: totalSize,
  );
}

/// Reads a specific slice of bytes directly from disk without buffering the whole file.
Future<Uint8List> readDiskSlice(
  String path,
  int offset,
  int length,
) async {
  if (length <= 0) return Uint8List(0);
  final file = File(path);
  if (!await file.exists()) {
    throw PathNotFoundException(
      path,
      const OSError('File does not exist or was removed', 2),
    );
  }

  final raf = await file.open(mode: FileMode.read);
  try {
    final fileLength = await raf.length();
    if (offset >= fileLength) {
      return Uint8List(0);
    }

    final bytesToRead = (offset + length > fileLength)
        ? (fileLength - offset)
        : length;

    await raf.setPosition(offset);
    final bytes = await raf.read(bytesToRead);
    return bytes;
  } finally {
    await raf.close();
  }
}
