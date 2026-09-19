/*
 * File: raw_stream_chunker.dart
 * Description: Low-memory streaming chunker slicing files into raw block partition chunks (.001, .002) for Telegram upload.
 */

import 'dart:math';
import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

import '../constants/app_constants.dart';
import 'raw_stream_native.dart'
    if (dart.library.js_interop) 'raw_stream_web.dart';

/// Low-memory streaming chunker partitioning files into pure raw block slices without any wrapper overhead.
///
/// Ensures the memory ceiling is strictly bounded to 1 chunk (< 20 MB) during upload,
/// without buffering entire files into RAM or creating temporary sliced duplicates on disk.
class RawStreamChunker {
  /// Default chunk size (19 MB).
  static const int defaultPartSize = AppConstants.chunkSizeBytes;

  /// Target file name.
  final String filename;

  /// Total size of the file payload in bytes.
  final int fileSize;

  /// Optional in-memory byte buffer (for web or small in-memory uploads).
  final Uint8List? bytes;

  /// Optional filesystem path to stream directly from disk without RAM buffering.
  final String? filePath;

  /// Chunk size in bytes (defaults to 19 MB).
  final int chunkSize;

  /// Total number of raw partition parts.
  final int partCount;

  /// Constructs a RawStreamChunker for disk or memory payloads.
  RawStreamChunker({
    required this.filename,
    required this.fileSize,
    this.bytes,
    this.filePath,
    this.chunkSize = defaultPartSize,
  })  : assert(bytes != null || filePath != null,
            'RawStreamChunker must have either in-memory bytes or a filesystem filePath.'),
        partCount = fileSize <= 0
            ? 1
            : (fileSize + chunkSize - 1) ~/ chunkSize;

  /// Formats the standard part name for a given 1-indexed part number (e.g., "video.mp4.001").
  String getPartName(int partIndex) {
    if (partCount == 1) {
      return filename;
    }
    final extensionNumber = partIndex.toString().padLeft(3, '0');
    return '$filename.$extensionNumber';
  }

  /// Computes the SHA-256 digest of a file on disk in streaming chunks without loading it into RAM.
  static Future<({String sha256, int fileSize})> hashFile(
    String filePath, {
    void Function(double progress)? onProgress,
  }) async {
    return await hashFilePath(filePath, onProgress: onProgress);
  }

  /// Computes SHA-256 for in-memory bytes in chunks with an optional progress callback.
  static Future<({String sha256, int fileSize})> hashBytes(
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    const streamChunkSize = 1024 * 1024;
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);

    for (var offset = 0; offset < data.length; offset += streamChunkSize) {
      final end = (offset + streamChunkSize).clamp(0, data.length);
      final slice = Uint8List.sublistView(data, offset, end);
      input.add(slice);
      if (onProgress != null && data.isNotEmpty) {
        onProgress(offset / data.length);
      }
      await Future.delayed(Duration.zero);
    }
    input.close();

    return (
      sha256: output.events.single.toString(),
      fileSize: data.length,
    );
  }

  /// Computes SHA-256 synchronously for small in-memory byte buffers.
  static ({String sha256, int fileSize}) hashBytesSync(Uint8List bytes) {
    return (
      sha256: sha256.convert(bytes).toString(),
      fileSize: bytes.length,
    );
  }

  /// Reads and returns pure byte slice for [partIndex] (1-indexed, 1 <= partIndex <= partCount).
  ///
  /// Bounded strictly to [chunkSize] bytes RAM overhead.
  Future<Uint8List> readPart(int partIndex) async {
    if (partIndex < 1 || partIndex > partCount) {
      throw RangeError.range(partIndex, 1, partCount, 'partIndex',
          'Invalid partIndex: $partIndex (total parts: $partCount)');
    }

    if (fileSize <= 0) {
      return Uint8List(0);
    }

    final startOffset = (partIndex - 1) * chunkSize;
    final lengthToRead = min(chunkSize, fileSize - startOffset);

    if (lengthToRead <= 0) {
      return Uint8List(0);
    }

    if (bytes != null) {
      return Uint8List.sublistView(
        bytes!,
        startOffset,
        startOffset + lengthToRead,
      );
    }

    return await readDiskSlice(
      filePath!,
      startOffset,
      lengthToRead,
    );
  }
}
