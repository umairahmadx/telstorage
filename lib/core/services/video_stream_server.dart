/*
 * File: video_stream_server.dart
 * Description: Loopback HTTP proxy serving HTTP 206 Partial Content byte ranges for on-demand video streaming and fast seeking.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/chunk_info.dart';
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import 'service_locator.dart';
import 'telegram_rate_limiter.dart';
import 'video_chunk_cache_manager.dart';

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

/// Callback definition for fetching chunk bytes (used for testing and abstraction).
typedef ChunkFetcher = Future<Uint8List> Function(
  String fileId,
  int chunkIndex,
  int chunkCount,
);

/// Callback definition for resolving FileRecord instances.
typedef FileRecordProvider = Future<FileRecord?> Function(String fileId);

/// Lightweight loopback HTTP server translating player Range requests into on-demand
/// Telegram chunk downloads.
class VideoStreamServer {
  VideoStreamServer._();

  /// Singleton instance of VideoStreamServer.
  static final VideoStreamServer instance = VideoStreamServer._();

  /// Default 19 MB slice size in bytes used by TelStorage.
  static const int defaultPartSize = 19 * 1024 * 1024;

  HttpServer? _server;
  int? _activePort;

  /// In-flight chunk downloads map to prevent duplicate concurrent network requests.
  final Map<String, Future<Uint8List>> _inFlightFetches = {};

  ChunkFetcher? _chunkFetcherForTesting;
  FileRecordProvider? _fileRecordProviderForTesting;

  /// Sets custom chunk fetcher for unit test isolation.
  void setChunkFetcherForTesting(ChunkFetcher? fetcher) {
    _chunkFetcherForTesting = fetcher;
  }

  /// Sets custom file record provider for unit test isolation.
  void setFileRecordProviderForTesting(FileRecordProvider? provider) {
    _fileRecordProviderForTesting = provider;
  }

  /// Calculates the ZIP local file header offset.
  /// For single-part uncompressed files, offset is 0.
  /// For multi-part ZIP STORE files, offset is 30 bytes + UTF-8 filename length.
  static int calculateHeaderOffset(String filename, {required bool isZipped}) {
    if (!isZipped) return 0;
    final nameBytes = utf8.encode(filename);
    return 30 + nameBytes.length;
  }

  /// Computes the chunk index and byte offset within that chunk for any video byte.
  static ChunkByteMapping mapByteToChunk({
    required int videoByteOffset,
    required int headerOffset,
    required int partSize,
  }) {
    final zipOffset = videoByteOffset + headerOffset;
    final chunkIndex = zipOffset ~/ partSize;
    final chunkOffset = zipOffset % partSize;
    return ChunkByteMapping(
      chunkIndex: chunkIndex,
      chunkOffset: chunkOffset,
    );
  }

  /// Parses RFC 7233 Range header strings (e.g. "bytes=0-1023", "bytes=1000-", "bytes=-500").
  static ByteRange? parseByteRange(String? header, int totalSize) {
    if (totalSize <= 0) return null;
    if (header == null || header.trim().isEmpty) {
      return ByteRange(0, totalSize - 1);
    }

    final trimmed = header.trim();
    if (!trimmed.startsWith('bytes=')) return null;

    final spec = trimmed.substring('bytes='.length);
    final parts = spec.split('-');
    if (parts.length != 2) return null;

    final rawStart = parts[0].trim();
    final rawEnd = parts[1].trim();

    if (rawStart.isNotEmpty && rawEnd.isNotEmpty) {
      final start = int.tryParse(rawStart);
      final end = int.tryParse(rawEnd);
      if (start == null || end == null || start > end || start >= totalSize) {
        return null;
      }
      return ByteRange(start, min(end, totalSize - 1));
    } else if (rawStart.isNotEmpty && rawEnd.isEmpty) {
      final start = int.tryParse(rawStart);
      if (start == null || start >= totalSize) return null;
      return ByteRange(start, totalSize - 1);
    } else if (rawStart.isEmpty && rawEnd.isNotEmpty) {
      final suffix = int.tryParse(rawEnd);
      if (suffix == null || suffix <= 0) return null;
      final start = max(0, totalSize - suffix);
      return ByteRange(start, totalSize - 1);
    }

    return null;
  }

  /// Starts the loopback HTTP server on an ephemeral loopback port.
  Future<int> start() async {
    if (kIsWeb) return 0;
    if (_server != null) return _activePort!;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _activePort = server.port;

    AppLogger.i('VideoStreamServer listening on http://127.0.0.1:$_activePort',
        tag: 'VideoStreamServer');

    server.listen(
      _handleRequest,
      onError: (e) => AppLogger.w('HttpServer error: $e', tag: 'VideoStreamServer'),
      cancelOnError: false,
    );

    return _activePort!;
  }

  /// Shuts down the loopback proxy server.
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _activePort = null;
      _inFlightFetches.clear();
      AppLogger.i('VideoStreamServer stopped', tag: 'VideoStreamServer');
    }
  }

  /// Resolves the loopback streaming URL for a given file ID.
  String getStreamUrl(String fileId) {
    final port = _activePort ?? 0;
    return 'http://127.0.0.1:$port/stream/$fileId';
  }

  /// Handles incoming HTTP GET requests for video streaming.
  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.length < 2 || segments[0] != 'stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final fileId = segments[1];
    final record = await _resolveFileRecord(fileId);
    if (record == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final totalBytes = max(1, (record.sizeMb * 1024 * 1024).round());
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final range = parseByteRange(rangeHeader, totalBytes);

    if (range == null) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalBytes');
      await request.response.close();
      return;
    }

    try {
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${range.start}-${range.end}/$totalBytes',
      );
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        record.mimeType.isNotEmpty ? record.mimeType : 'video/mp4',
      );
      request.response.contentLength = range.length;

      final isZipped = record.chunkCount > 1;
      final headerOffset = calculateHeaderOffset(record.name, isZipped: isZipped);
      const partSize = defaultPartSize;

      final zStart = range.start + headerOffset;
      final zEnd = range.end + headerOffset;
      final startChunk = zStart ~/ partSize;
      final endChunk = zEnd ~/ partSize;

      for (var chunkIdx = startChunk; chunkIdx <= endChunk; chunkIdx++) {
        final chunkBytes = await _getOrFetchChunk(record, chunkIdx);
        final chunkBase = chunkIdx * partSize;
        final sliceStart = max(0, zStart - chunkBase).clamp(0, chunkBytes.length);
        final sliceEnd = min(chunkBytes.length, zEnd - chunkBase + 1);

        if (sliceEnd > sliceStart) {
          final slice = Uint8List.sublistView(chunkBytes, sliceStart, sliceEnd);
          request.response.add(slice);
          await request.response.flush();
        }
      }

      await request.response.close();
    } on SocketException catch (_) {
      // Normal occurrence when video player cancels stream on user seek/scrub
    } on HttpException catch (_) {
      // Normal connection abort
    } catch (e) {
      AppLogger.w('Streaming error for $fileId: $e', tag: 'VideoStreamServer');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<FileRecord?> _resolveFileRecord(String fileId) async {
    if (_fileRecordProviderForTesting != null) {
      return _fileRecordProviderForTesting!(fileId);
    }
    if (ServiceLocator.instance.isInitialized) {
      return ServiceLocator.instance.hive.getFile(fileId);
    }
    return null;
  }

  Future<Uint8List> _getOrFetchChunk(FileRecord record, int chunkIdx) async {
    // 1. Check local disk cache
    final cached = await VideoChunkCacheManager.instance.getCachedChunk(record.fileId, chunkIdx);
    if (cached != null && cached.existsSync()) {
      return await cached.readAsBytes();
    }

    // 2. Deduplicate in-flight fetches
    final cacheKey = '${record.fileId}:$chunkIdx';
    if (_inFlightFetches.containsKey(cacheKey)) {
      return await _inFlightFetches[cacheKey]!;
    }

    final future = _executeChunkFetch(record, chunkIdx);
    _inFlightFetches[cacheKey] = future;

    try {
      final bytes = await future;
      await VideoChunkCacheManager.instance.saveChunk(record.fileId, chunkIdx, bytes);
      return bytes;
    } finally {
      _inFlightFetches.remove(cacheKey);
    }
  }

  Future<Uint8List> _executeChunkFetch(FileRecord record, int chunkIdx) async {
    if (_chunkFetcherForTesting != null) {
      return _chunkFetcherForTesting!(record.fileId, chunkIdx, record.chunkCount);
    }

    final telegram = ServiceLocator.instance.telegram;

    if (record.metadataFileId != null) {
      // Fetch metadata to find exact chunk fileId
      final metaBytes = await telegram.downloadByFileId(
        record.metadataFileId!,
        RequestPriority.immediate,
      );
      final meta = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
      final rawChunks = (meta['chunks'] as List)
          .map((c) => ChunkInfo.fromJson(c as Map<String, dynamic>))
          .toList();

      final targetChunk = rawChunks.firstWhere(
        (c) => c.index == chunkIdx,
        orElse: () => throw Exception('Chunk $chunkIdx not found in metadata'),
      );
      return await telegram.downloadByFileId(
        targetChunk.fileId!,
        RequestPriority.immediate,
      );
    } else {
      // Single chunk fallback
      return await telegram.downloadByFileId(
        record.fileId,
        RequestPriority.immediate,
      );
    }
  }
}
