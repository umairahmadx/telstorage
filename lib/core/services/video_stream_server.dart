/*
 * File: video_stream_server.dart
 * Description: Loopback HTTP proxy serving RFC 7233/9110 HTTP 206 Partial Content byte ranges for on-demand video streaming.
 */

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/chunk_info.dart';
import '../models/file_record.dart';
import '../models/video_stream_models.dart';
import '../utils/app_logger.dart';
import 'service_locator.dart';
import 'telegram_rate_limiter.dart';
import 'video_prefetch_coordinator.dart';
import 'video_stream_pipeliner.dart';

export '../models/video_stream_models.dart';

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
  int _cacheGeneration = 0;

  final Map<String, Future<Uint8List>> _inFlightFetches = {}; // In-flight chunk downloads
  final Map<String, RegisteredStreamFile> _activeFiles = {}; // Registered stream files
  final Map<String, Future<Map<int, ChunkInfo>>> _inFlightMetadata = {}; // In-flight metadata
  final Map<String, Map<int, ChunkInfo>> _metadataCache = {}; // Validated metadata cache

  FileRecordProvider? _fileRecordProviderForTesting;
  final VideoPrefetchCoordinator _prefetchCoordinator = VideoPrefetchCoordinator();
  final VideoStreamPipeliner _pipeliner = VideoStreamPipeliner();

  /// Sliding-window prefetch coordinator.
  VideoPrefetchCoordinator get prefetchCoordinator => _prefetchCoordinator;

  /// Real-time packet stream pipeliner.
  VideoStreamPipeliner get pipeliner => _pipeliner;

  /// Registers an active [file] record in memory for stream resolution and returns an idempotent handle.
  StreamRegistration registerFile(FileRecord file) {
    final existing = _activeFiles[file.fileId];
    if (existing != null) {
      if (existing.file.chunkCount != file.chunkCount ||
          existing.file.metadataFileId != file.metadataFileId) {
        throw ArgumentError(
          'Cannot register file ${file.fileId} with conflicting metadata or chunk count',
        );
      }
      existing.file = file;
      existing.refCount++;
    } else {
      _activeFiles[file.fileId] = RegisteredStreamFile(file);
    }
    return StreamRegistration(file.fileId, () => unregisterFile(file.fileId));
  }

  /// Unregisters an active file record when playback ceases.
  void unregisterFile(String fileId) {
    final existing = _activeFiles[fileId];
    if (existing != null) {
      existing.refCount--;
      if (existing.refCount <= 0) {
        _activeFiles.remove(fileId);
        _cacheGeneration++;
        _metadataCache.removeWhere((k, _) => k.startsWith('$fileId:'));
        _inFlightMetadata.removeWhere((k, _) => k.startsWith('$fileId:'));
        _pipeliner.cancelForFile(fileId);
        _prefetchCoordinator.cancelForFile(fileId);
      }
    }
  }

  /// Sets custom chunk fetcher for unit test isolation.
  void setChunkFetcherForTesting(ChunkFetcher? fetcher) {
    if (fetcher != null) {
      _prefetchCoordinator.setDownloaderForTesting(
        (record, chunkIdx, priority) => fetcher(record.fileId, chunkIdx, record.chunkCount),
      );
      _pipeliner.setStreamFetcherForTesting((fileId, chunkIndex) async* {
        final record = _activeFiles[fileId]?.file;
        final totalChunks = record?.chunkCount ?? 1;
        yield await fetcher(fileId, chunkIndex, totalChunks);
      });
    } else {
      _prefetchCoordinator.setDownloaderForTesting(null);
      _pipeliner.setStreamFetcherForTesting(null);
    }
  }

  /// Sets custom stream fetcher for unit test isolation.
  void setStreamFetcherForTesting(StreamFetcher? fetcher) =>
      _pipeliner.setStreamFetcherForTesting(fetcher);

  /// Sets custom file record provider for unit test isolation.
  void setFileRecordProviderForTesting(FileRecordProvider? provider) {
    _fileRecordProviderForTesting = provider;
  }

  int _partSize = defaultPartSize;
  /// Sets custom part size for unit testing boundary conditions.
  void setPartSizeForTesting(int? size) => _partSize = size ?? defaultPartSize;

  /// Computes the chunk index and byte offset within that chunk for any video byte.
  static ChunkByteMapping mapByteToChunk({
    required int videoByteOffset,
    required int partSize,
  }) {
    return ChunkByteMapping(
      chunkIndex: videoByteOffset ~/ partSize,
      chunkOffset: videoByteOffset % partSize,
    );
  }

  /// Parses RFC 7233 / RFC 9110 Range header strings.
  /// Returns null if header is malformed, unsatisfiable, or requests unsupported multiple ranges.
  static ByteRange? parseByteRange(String? header, int totalSize) =>
      ByteRange.parse(header, totalSize);

  /// Resolves the appropriate media (video or audio) MIME type based on record and file extension.
  static String resolveMimeType(String filename, String? recordMime) {
    if (recordMime != null && recordMime.isNotEmpty && recordMime != 'application/octet-stream') {
      return recordMime;
    }
    final lower = filename.toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/mp4';
    if (lower.endsWith('.ogg') || lower.endsWith('.oga') || lower.endsWith('.opus')) return 'audio/ogg';
    if (lower.endsWith('.flac')) return 'audio/flac';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'video/mp4';
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
      _cacheGeneration++;
      _pipeliner.cancelAll();
      await _prefetchCoordinator.cancelAll();
      _inFlightFetches.clear();
      _activeFiles.clear();
      _metadataCache.clear();
      _inFlightMetadata.clear();
      _fileRecordProviderForTesting = null;
      _prefetchCoordinator.setDownloaderForTesting(null);
      _pipeliner.setStreamFetcherForTesting(null);
      _partSize = defaultPartSize;
      AppLogger.i('VideoStreamServer stopped', tag: 'VideoStreamServer');
    }
  }

  /// Resolves the loopback streaming URL for a given file ID and optional filename.
  String getStreamUrl(String fileId, [String? filename]) {
    final port = _activePort;
    if (port == null) throw StateError('VideoStreamServer must be started before getStreamUrl');
    final segs = (filename != null && filename.isNotEmpty) ? ['stream', fileId, filename] : ['stream', fileId];
    return Uri(scheme: 'http', host: '127.0.0.1', port: port, pathSegments: segs).toString();
  }

  /// Handles incoming HTTP GET and HEAD requests for video streaming.
  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }

    final segments = request.uri.pathSegments;
    if (segments.isEmpty || segments[0] != 'stream' || segments.length < 2 || segments.length > 3) {
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

    final metaId = record.metadataFileId?.trim();
    if ((metaId == null || metaId.isEmpty) && record.chunkCount > 1) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.text;
      request.response.write('Multi-chunk file missing metadataFileId for $fileId');
      await request.response.close();
      return;
    }

    Map<int, ChunkInfo>? chunkMap;
    if (metaId != null) {
      try {
        chunkMap = await _getOrFetchMetadata(record);
      } catch (e, st) {
        AppLogger.e('Metadata preflight failed for $fileId: $e',
            tag: 'VideoStreamServer', error: e, stackTrace: st);
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.text;
        request.response.write('Internal Server Error: $e');
        await request.response.close();
        return;
      }
    }

    final regFile = _activeFiles[fileId];
    final totalBytes = regFile?.totalBytes ?? max(1, (record.sizeMb * 1024 * 1024).round());

    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final hasRangeHeader = rangeHeader != null && rangeHeader.trim().isNotEmpty;
    final range = parseByteRange(rangeHeader, totalBytes);

    if (range == null) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.contentLength = 0;
      request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalBytes');
      await request.response.close();
      return;
    }

    try {
      request.response.statusCode = hasRangeHeader ? HttpStatus.partialContent : HttpStatus.ok;
      if (hasRangeHeader) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes ${range.start}-${range.end}/$totalBytes',
        );
      }

      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        resolveMimeType(record.name, record.mimeType),
      );
      request.response.contentLength = range.length;

      if (request.method == 'HEAD') {
        await request.response.close();
        return;
      }

      final partSize = record.chunkCount > 1 ? _partSize : max(_partSize, totalBytes);
      final startChunk = range.start ~/ partSize;
      final endChunk = range.end ~/ partSize;

      if (record.chunkCount > 1) {
        _prefetchCoordinator.onChunkRequested(record, startChunk, chunkMap: chunkMap);
      }

      final wasActiveAtStart = _activeFiles.containsKey(fileId);
      var totalWritten = 0;
      for (var chunkIdx = startChunk; chunkIdx <= endChunk; chunkIdx++) {
        if (wasActiveAtStart && !_activeFiles.containsKey(fileId)) break;

        final chunkBase = chunkIdx * partSize;
        final sliceStart = max(0, range.start - chunkBase);
        final sliceEnd = min(partSize, range.end - chunkBase + 1);

        if (sliceEnd > sliceStart) {
          final written = await _pipeliner.pipeChunkRange(
            record: record,
            chunkIndex: chunkIdx,
            sliceStart: sliceStart,
            sliceEnd: sliceEnd,
            output: request.response,
            chunkMap: chunkMap,
          );
          totalWritten += written;
          if (wasActiveAtStart && !_activeFiles.containsKey(fileId)) break;
        }
      }

      if (wasActiveAtStart && !_activeFiles.containsKey(fileId)) {
        try { await request.response.close(); } catch (_) {}
        return;
      }

      if (totalWritten != range.length) {
        throw StateError('Stream underflow: expected ${range.length} bytes, wrote $totalWritten');
      }

      await request.response.close();
    } on UnsupportedError catch (e) {
      AppLogger.w('Unsupported media for $fileId: $e', tag: 'VideoStreamServer');
      try {
        request.response.contentLength = 0;
        request.response.headers.removeAll(HttpHeaders.contentRangeHeader);
        request.response.statusCode = HttpStatus.unsupportedMediaType;
        await request.response.close();
      } catch (_) {}
      return;
    } on SocketException catch (_) {
      // Normal occurrence when video player cancels stream on user seek/scrub
    } on HttpException catch (_) {
      // Normal connection abort
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) {
        AppLogger.w('Dio error streaming $fileId: $e', tag: 'VideoStreamServer');
      }
    } catch (e, st) {
      AppLogger.e('Streaming error for $fileId range=${range.start}-${range.end}: $e',
          tag: 'VideoStreamServer', error: e, stackTrace: st);
      try {
        request.response.contentLength = -1;
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.removeAll(HttpHeaders.contentRangeHeader);
        request.response.headers.contentType = ContentType.text;
        request.response.write('Internal Server Error: $e');
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<FileRecord?> _resolveFileRecord(String fileId) async {
    final active = _activeFiles[fileId];
    if (active != null) return active.file;
    if (_fileRecordProviderForTesting != null) {
      return _fileRecordProviderForTesting!(fileId);
    }
    return null;
  }

  String _cacheKey(FileRecord record) {
    return '${record.fileId}:${record.metadataFileId ?? "direct"}';
  }



  Future<Map<int, ChunkInfo>> _getOrFetchMetadata(FileRecord record) {
    final key = _cacheKey(record);
    final cached = _metadataCache[key];
    if (cached != null) return Future.value(cached);

    final inFlight = _inFlightMetadata[key];
    if (inFlight != null) return inFlight;

    final gen = _cacheGeneration;
    final future = _executeMetadataFetch(record);
    _inFlightMetadata[key] = future;

    return future.then((map) {
      if (gen == _cacheGeneration && identical(_inFlightMetadata[key], future)) {
        _metadataCache[key] = map;
        _inFlightMetadata.remove(key);
      }
      return map;
    }).whenComplete(() {
      if (identical(_inFlightMetadata[key], future)) _inFlightMetadata.remove(key);
    });
  }

  Future<Map<int, ChunkInfo>> _executeMetadataFetch(FileRecord record) async {
    final telegram = ServiceLocator.instance.telegram;
    final metaBytes = await telegram.downloadByFileId(
      record.metadataFileId!,
      RequestPriority.immediate,
    );
    return ChunkMetadataParser.parseAndValidate(
      fileId: record.fileId,
      chunkCount: record.chunkCount,
      metaBytes: metaBytes,
    );
  }
}
