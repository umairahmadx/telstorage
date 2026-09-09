/*
 * File: video_stream_models.dart
 * Description: Data models and registration handles for video streaming, byte range mapping, and chunk layouts.
 */

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'chunk_info.dart';
import 'file_record.dart';

/// Represents a byte range slice requested by an HTTP client.
class ByteRange {
  /// Starting byte offset (inclusive).
  final int start;

  /// Ending byte offset (inclusive).
  final int end;

  /// Constructs a ByteRange with validated bounds.
  const ByteRange(this.start, this.end);

  /// Number of bytes spanned by this range.
  int get length => (end - start) + 1;

  /// Parses RFC 7233 / RFC 9110 Range header strings.
  /// Returns null if header is malformed, unsatisfiable, or requests unsupported multiple ranges.
  static ByteRange? parse(String? header, int totalSize) {
    if (totalSize <= 0) return null;
    if (header == null || header.trim().isEmpty) {
      return ByteRange(0, totalSize - 1);
    }

    final trimmed = header.trim();
    if (!trimmed.toLowerCase().startsWith('bytes=')) return null;

    final spec = trimmed.substring('bytes='.length).trim();
    if (spec.contains(',')) return null;

    final parts = spec.split('-');
    if (parts.length != 2) return null;

    final rawStart = parts[0].trim();
    final rawEnd = parts[1].trim();

    if (rawStart.isNotEmpty && rawEnd.isNotEmpty) {
      final start = int.tryParse(rawStart);
      final end = int.tryParse(rawEnd);
      if (start == null || end == null || start < 0 || end < 0 || start > end || start >= totalSize) {
        return null;
      }
      return ByteRange(start, min(end, totalSize - 1));
    } else if (rawStart.isNotEmpty && rawEnd.isEmpty) {
      final start = int.tryParse(rawStart);
      if (start == null || start < 0 || start >= totalSize) return null;
      return ByteRange(start, totalSize - 1);
    } else if (rawStart.isEmpty && rawEnd.isNotEmpty) {
      final suffix = int.tryParse(rawEnd);
      if (suffix == null || suffix <= 0) return null;
      final start = max(0, totalSize - suffix);
      return ByteRange(start, totalSize - 1);
    }

    return null;
  }
}

/// Represents the mathematical mapping of a video byte to a Telegram chunk.
class ChunkByteMapping {
  /// Zero-based index of the Telegram chunk.
  final int chunkIndex;

  /// Byte offset within the uncompressed chunk.
  final int chunkOffset;

  /// Constructs ChunkByteMapping.
  const ChunkByteMapping({
    required this.chunkIndex,
    required this.chunkOffset,
  });
}

/// Represents the immutable byte boundaries of a chunk within a file stream.
class ChunkByteRange {
  /// Zero-based chunk index.
  final int chunkIndex;

  /// One-based Telegram metadata chunk index.
  final int metadataIndex;

  /// Start byte offset in the overall file stream (inclusive).
  final int startByte;

  /// End byte offset in the overall file stream (inclusive).
  final int endByte;

  /// Underlying chunk information from Telegram metadata.
  final ChunkInfo chunkInfo;

  /// Constructs a ChunkByteRange descriptor.
  const ChunkByteRange({
    required this.chunkIndex,
    required this.metadataIndex,
    required this.startByte,
    required this.endByte,
    required this.chunkInfo,
  });

  /// Total bytes spanned by this chunk.
  int get length => (endByte - startByte) + 1;
}

/// Idempotent registration handle ensuring safe single-ownership unregistration.
class StreamRegistration {
  /// File ID associated with this registration.
  final String fileId;

  final VoidCallback _onDispose;
  bool _isDisposed = false;

  /// Whether this registration handle has already been disposed.
  bool get isDisposed => _isDisposed;

  /// Constructs a StreamRegistration handle.
  StreamRegistration(this.fileId, this._onDispose);

  /// Decrements registration ref-count exactly once.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _onDispose();
  }
}

/// Internal reference-counted registration container for active streaming files.
class RegisteredStreamFile {
  /// Active FileRecord instance.
  FileRecord file;

  /// Reference count of active players holding a handle.
  int refCount;

  /// Constructs a RegisteredStreamFile with initial count of 1.
  RegisteredStreamFile(this.file) : refCount = 1;
}

/// Extracted ZIP local file header metadata for video streaming.
class ZipHeaderInfo {
  /// Compression method (0 = STORE, 8 = DEFLATE).
  final int compressionMethod;

  /// Exact uncompressed size in bytes.
  final int uncompressedSize;

  /// Byte offset from start of chunk 0 to the start of uncompressed payload data.
  final int headerOffset;

  /// Constructs a ZipHeaderInfo descriptor.
  const ZipHeaderInfo({
    required this.compressionMethod,
    required this.uncompressedSize,
    required this.headerOffset,
  });

  /// Parses ZIP Local File Header from chunk 0 bytes, or null if not a valid ZIP header.
  static ZipHeaderInfo? tryParse(Uint8List chunk0) {
    if (chunk0.length < 30) return null;
    final view = ByteData.sublistView(chunk0);
    final sig = view.getUint32(0, Endian.little);
    if (sig != 0x04034b50) return null;

    final method = view.getUint16(8, Endian.little);
    final uncompressedSize = view.getUint32(22, Endian.little);
    final nameLen = view.getUint16(26, Endian.little);
    final extraLen = view.getUint16(28, Endian.little);
    final headerOffset = 30 + nameLen + extraLen;

    return ZipHeaderInfo(
      compressionMethod: method,
      uncompressedSize: uncompressedSize,
      headerOffset: headerOffset,
    );
  }
}

/// Validates and parses chunk metadata from raw Telegram JSON bytes.
class ChunkMetadataParser {
  /// Parses and validates chunk mapping from [metaBytes].
  static Map<int, ChunkInfo> parseAndValidate({
    required String fileId,
    required int chunkCount,
    required Uint8List metaBytes,
  }) {
    final meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
    final rawList = meta['chunks'] as List?;
    if (rawList == null || rawList.isEmpty) {
      throw Exception('Metadata for $fileId contains no chunks');
    }

    final rawChunks = rawList
        .map((c) => ChunkInfo.fromJson(c as Map<String, dynamic>))
        .toList();

    final chunkMap = <int, ChunkInfo>{};
    for (final chunk in rawChunks) {
      if (chunk.fileId == null || chunk.fileId!.isEmpty) {
        throw Exception('Chunk ${chunk.index} has empty fileId for $fileId');
      }
      if (chunk.sizeMb <= 0) {
        throw Exception('Chunk ${chunk.index} has invalid non-positive size for $fileId');
      }
      if (chunkMap.containsKey(chunk.index)) {
        throw Exception('Duplicate chunk index ${chunk.index} in metadata for $fileId');
      }
      chunkMap[chunk.index] = chunk;
    }

    final isZeroBased = !chunkMap.containsKey(1) && chunkMap.containsKey(0);
    final expectedCount = chunkCount > 0 ? chunkCount : rawChunks.length;
    final startIndex = isZeroBased ? 0 : 1;
    final endIndex = isZeroBased ? expectedCount - 1 : expectedCount;

    for (var i = startIndex; i <= endIndex; i++) {
      if (!chunkMap.containsKey(i)) {
        throw Exception('Missing chunk index $i in metadata for $fileId');
      }
    }

    return chunkMap;
  }
}

