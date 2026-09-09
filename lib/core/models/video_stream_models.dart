/*
 * File: video_stream_models.dart
 * Description: Data models and registration handles for video streaming, byte range mapping, and chunk layouts.
 */

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
