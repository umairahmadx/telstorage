/*
 * File: video_stream_multi_chunk_test.dart
 * Description: Unit and integration tests for multi-chunk video streaming, HEAD probing, MIME resolution, and STORE chunk slicing.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/video_chunk_cache_manager.dart';
import 'package:telstorage/core/services/video_stream_server.dart';
import 'package:telstorage/core/utils/zip_stream_chunker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoStreamServer server;
  late Directory tempDir;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('vss_multi_test_');
    VideoChunkCacheManager.instance.setBaseDirForTesting(tempDir);
    server = VideoStreamServer.instance;
  });

  tearDown(() async {
    await server.stop();
    server.setFileRecordProviderForTesting(null);
    server.setChunkFetcherForTesting(null);
    server.setPartSizeForTesting(null);
    VideoChunkCacheManager.instance.setBaseDirForTesting(null);
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('ZipHeaderInfo & MIME Resolution Unit Tests', () {
    test('ZipHeaderInfo.tryParse extracts STORE and DEFLATE headers correctly', () {
      expect(ZipHeaderInfo.tryParse(Uint8List(20)), isNull);

      final invalidSig = Uint8List(35);
      expect(ZipHeaderInfo.tryParse(invalidSig), isNull);

      final validStore = ZipStreamChunker.createLocalHeader(
        filename: 'test.mp4',
        crc32: 12345,
        fileSize: 54321,
      );
      final storeInfo = ZipHeaderInfo.tryParse(validStore);
      expect(storeInfo, isNotNull);
      expect(storeInfo!.compressionMethod, equals(0));
      expect(storeInfo.uncompressedSize, equals(54321));
      expect(storeInfo.headerOffset, equals(30 + utf8.encode('test.mp4').length));

      // Test deflate header (method 8)
      final deflateBytes = Uint8List.fromList(validStore);
      ByteData.sublistView(deflateBytes).setUint16(8, 8, Endian.little);
      final deflateInfo = ZipHeaderInfo.tryParse(deflateBytes);
      expect(deflateInfo, isNotNull);
      expect(deflateInfo!.compressionMethod, equals(8));
    });

    test('resolveMimeType accurately maps video extensions and preserves custom MIME', () {
      expect(VideoStreamServer.resolveMimeType('movie.mp4', null), equals('video/mp4'));
      expect(VideoStreamServer.resolveMimeType('movie.mov', ''), equals('video/quicktime'));
      expect(VideoStreamServer.resolveMimeType('clip.MOV', 'application/octet-stream'), equals('video/quicktime'));
      expect(VideoStreamServer.resolveMimeType('video.mkv', null), equals('video/x-matroska'));
      expect(VideoStreamServer.resolveMimeType('stream.webm', null), equals('video/webm'));
      expect(VideoStreamServer.resolveMimeType('custom.mp4', 'video/custom'), equals('video/custom'));
    });
  });

  group('Multi-Chunk & HEAD Loopback HTTP Tests', () {
    test('HEAD request returns 200/206 headers without response body', () async {
      final payload = Uint8List.fromList(List.generate(100, (i) => i % 256));
      final testRecord = FileRecord(
        fileId: 'stream_vid_head_test',
        name: 'head_clip.mp4',
        metadataMessageId: 80,
        sizeMb: payload.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_hash',
      );

      server.registerFile(testRecord);
      server.setChunkFetcherForTesting((id, idx, count) async => payload);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);

        // HEAD un-ranged
        final req1 = await client.headUrl(Uri.parse(streamUrl));
        final res1 = await req1.close();
        expect(res1.statusCode, equals(HttpStatus.ok));
        expect(res1.headers.value(HttpHeaders.acceptRangesHeader), equals('bytes'));
        expect(res1.headers.value(HttpHeaders.contentTypeHeader), equals('video/mp4'));
        expect(res1.contentLength, equals(payload.length));
        final body1 = await res1.fold<List<int>>([], (p, e) => p..addAll(e));
        expect(body1, isEmpty);

        // HEAD with Range
        final req2 = await client.headUrl(Uri.parse(streamUrl));
        req2.headers.set(HttpHeaders.rangeHeader, 'bytes=10-29');
        final res2 = await req2.close();
        expect(res2.statusCode, equals(HttpStatus.partialContent));
        expect(res2.headers.value(HttpHeaders.contentRangeHeader), equals('bytes 10-29/${payload.length}'));
        expect(res2.contentLength, equals(20));
        final body2 = await res2.fold<List<int>>([], (p, e) => p..addAll(e));
        expect(body2, isEmpty);
      } finally {
        client.close();
      }
    });

    test('Multi-chunk STORE stream with trailer slices exact video bytes only', () async {
      final rawVideo = Uint8List.fromList(List.generate(5000, (i) => (i * 7) % 256));
      const filename = 'camera_vid.mp4';
      final header = ZipStreamChunker.createLocalHeader(
        filename: filename,
        crc32: 9999,
        fileSize: rawVideo.length,
      );
      final trailer = ZipStreamChunker.createCentralDirectoryAndEocd(
        filename: filename,
        crc32: 9999,
        fileSize: rawVideo.length,
      );

      // Build realistic full ZIP: header + video + Central Directory + EOCD
      const partSize = 3000;
      final fullZipBytes = Uint8List(header.length + rawVideo.length + trailer.length);
      fullZipBytes.setRange(0, header.length, header);
      fullZipBytes.setRange(header.length, header.length + rawVideo.length, rawVideo);
      fullZipBytes.setRange(header.length + rawVideo.length, fullZipBytes.length, trailer);

      final chunk0 = Uint8List.sublistView(fullZipBytes, 0, partSize);
      final chunk1 = Uint8List.sublistView(fullZipBytes, partSize);

      final testRecord = FileRecord(
        fileId: 'store_multi_vid_123',
        name: filename,
        metadataMessageId: 85,
        metadataFileId: 'store_meta_id',
        sizeMb: rawVideo.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: 'dummy_sha',
      );

      final metadataJson = jsonEncode({
        'file_id': testRecord.fileId,
        'name': testRecord.name,
        'size_mb': testRecord.sizeMb,
        'chunk_count': 2,
        'chunks': [
          {'index': 1, 'message_id': 86, 'file_id': 'tg_store_chunk_1', 'size_mb': 1.0, 'part_name': 'part1'},
          {'index': 2, 'message_id': 87, 'file_id': 'tg_store_chunk_2', 'size_mb': 1.0, 'part_name': 'part2'},
        ],
      });

      final fakeTelegram = FakeMultiStreamTelegram();
      fakeTelegram.files['store_meta_id'] = Uint8List.fromList(utf8.encode(metadataJson));
      fakeTelegram.files['tg_store_chunk_1'] = chunk0;
      fakeTelegram.files['tg_store_chunk_2'] = chunk1;

      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);

      server.registerFile(testRecord);
      server.setChunkFetcherForTesting(null);
      server.setPartSizeForTesting(partSize);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);

        // Cross-chunk boundary range (chunk 0 → chunk 1)
        final req = await client.getUrl(Uri.parse(streamUrl));
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=2800-3200');
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.partialContent));
        expect(res.contentLength, equals(401));
        final received = await res.fold<List<int>>([], (p, e) => p..addAll(e));
        expect(received, equals(rawVideo.sublist(2800, 3201)));

        // EOF range — the exact scenario that previously served ZIP trailer
        // bytes as video data, causing ExoPlayer Source error.
        final reqEnd = await client.getUrl(Uri.parse(streamUrl));
        reqEnd.headers.set(HttpHeaders.rangeHeader, 'bytes=4900-4999');
        final resEnd = await reqEnd.close();
        expect(resEnd.statusCode, equals(HttpStatus.partialContent));
        expect(resEnd.contentLength, equals(100));
        final receivedEnd = await resEnd.fold<List<int>>([], (p, e) => p..addAll(e));
        expect(receivedEnd, equals(rawVideo.sublist(4900, 5000)));
      } finally {
        client.close();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });

    test('Multi-chunk STORE full un-ranged GET returns exact video payload', () async {
      final rawVideo = Uint8List.fromList(List.generate(4000, (i) => (i * 3) % 256));
      const filename = 'full_get_vid.mp4';
      final header = ZipStreamChunker.createLocalHeader(
        filename: filename, crc32: 1111, fileSize: rawVideo.length,
      );
      final trailer = ZipStreamChunker.createCentralDirectoryAndEocd(
        filename: filename, crc32: 1111, fileSize: rawVideo.length,
      );

      const partSize = 2500;
      final fullZip = Uint8List(header.length + rawVideo.length + trailer.length);
      fullZip.setRange(0, header.length, header);
      fullZip.setRange(header.length, header.length + rawVideo.length, rawVideo);
      fullZip.setRange(header.length + rawVideo.length, fullZip.length, trailer);

      final chunk0 = Uint8List.sublistView(fullZip, 0, partSize);
      final chunk1 = Uint8List.sublistView(fullZip, partSize);

      final testRecord = FileRecord(
        fileId: 'full_get_multi_vid',
        name: filename,
        metadataMessageId: 100,
        metadataFileId: 'full_get_meta_id',
        sizeMb: rawVideo.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: 'dummy_full',
      );

      final metaJson = jsonEncode({
        'file_id': testRecord.fileId, 'name': testRecord.name,
        'size_mb': testRecord.sizeMb, 'chunk_count': 2,
        'chunks': [
          {'index': 1, 'message_id': 101, 'file_id': 'fg_c1', 'size_mb': 1.0},
          {'index': 2, 'message_id': 102, 'file_id': 'fg_c2', 'size_mb': 1.0},
        ],
      });

      final fakeTelegram = FakeMultiStreamTelegram();
      fakeTelegram.files['full_get_meta_id'] = Uint8List.fromList(utf8.encode(metaJson));
      fakeTelegram.files['fg_c1'] = chunk0;
      fakeTelegram.files['fg_c2'] = chunk1;

      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);
      server.registerFile(testRecord);
      server.setChunkFetcherForTesting(null);
      server.setPartSizeForTesting(partSize);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);
        // No Range header — full file fetch
        final req = await client.getUrl(Uri.parse(streamUrl));
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.ok));
        expect(res.contentLength, equals(rawVideo.length));
        final received = await res.fold<List<int>>([], (p, e) => p..addAll(e));
        expect(received, equals(rawVideo));
      } finally {
        client.close();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });

    test('Uint32 overflow (>4 GB) falls back to record.sizeMb for totalBytes', () async {
      // Simulate a ZIP header where uncompressedSize is 0 (Uint32 overflow)
      const filename = 'huge_vid.mp4';
      const fakeSizeMb = 25.0; // 25 MB
      final fakeVideoSize = (fakeSizeMb * 1024 * 1024).round();
      final header = ZipStreamChunker.createLocalHeader(
        filename: filename, crc32: 5555, fileSize: fakeVideoSize,
      );

      // Manually zero out the uncompressedSize field at offset 22 to simulate overflow
      final chunk0 = Uint8List.fromList(header);
      ByteData.sublistView(chunk0).setUint32(22, 0, Endian.little);
      // Also zero out compressedSize at offset 18 for consistency
      ByteData.sublistView(chunk0).setUint32(18, 0, Endian.little);

      final testRecord = FileRecord(
        fileId: 'huge_vid_overflow',
        name: filename,
        metadataMessageId: 110,
        metadataFileId: 'huge_meta_id',
        sizeMb: fakeSizeMb,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: 'dummy_huge',
      );

      final metaJson = jsonEncode({
        'file_id': testRecord.fileId, 'name': testRecord.name,
        'size_mb': testRecord.sizeMb, 'chunk_count': 2,
        'chunks': [
          {'index': 1, 'message_id': 111, 'file_id': 'huge_c1', 'size_mb': 19.0},
          {'index': 2, 'message_id': 112, 'file_id': 'huge_c2', 'size_mb': 6.0},
        ],
      });

      final fakeTelegram = FakeMultiStreamTelegram();
      fakeTelegram.files['huge_meta_id'] = Uint8List.fromList(utf8.encode(metaJson));
      // Chunk 0 is the tampered header (uncompressedSize=0)
      fakeTelegram.files['huge_c1'] = chunk0;
      // Chunk 1 is arbitrary bytes — we only test HEAD, not full payload
      fakeTelegram.files['huge_c2'] = Uint8List(100);

      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);
      server.registerFile(testRecord);
      server.setChunkFetcherForTesting(null);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);
        // HEAD request to verify advertised Content-Length equals sizeMb fallback
        final req = await client.headUrl(Uri.parse(streamUrl));
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.ok));
        expect(res.contentLength, equals(fakeVideoSize));
        await res.drain();
      } finally {
        client.close();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });

    test('Non-STORE compression method (e.g. DEFLATE method 8) returns 415 unsupportedMediaType', () async {
      const filename = 'deflate_rejected.mp4';
      final header = ZipStreamChunker.createLocalHeader(
        filename: filename, crc32: 8888, fileSize: 10000,
      );
      final chunk0 = Uint8List.fromList(header);
      // Set compression method to 8 (DEFLATE)
      ByteData.sublistView(chunk0).setUint16(8, 8, Endian.little);

      final testRecord = FileRecord(
        fileId: 'deflate_reject_123',
        name: filename,
        metadataMessageId: 95,
        metadataFileId: 'deflate_reject_meta',
        sizeMb: 10000 / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: 'dummy_reject',
      );

      final metaJson = jsonEncode({
        'file_id': testRecord.fileId, 'name': testRecord.name,
        'size_mb': testRecord.sizeMb, 'chunk_count': 2,
        'chunks': [
          {'index': 1, 'message_id': 96, 'file_id': 'rej_c1', 'size_mb': 1.0},
          {'index': 2, 'message_id': 97, 'file_id': 'rej_c2', 'size_mb': 1.0},
        ],
      });

      final fakeTelegram = FakeMultiStreamTelegram();
      fakeTelegram.files['deflate_reject_meta'] = Uint8List.fromList(utf8.encode(metaJson));
      fakeTelegram.files['rej_c1'] = chunk0;
      fakeTelegram.files['rej_c2'] = Uint8List(100);

      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);

      server.registerFile(testRecord);
      server.setChunkFetcherForTesting(null);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);
        final req = await client.getUrl(Uri.parse(streamUrl));
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.unsupportedMediaType));
        await res.drain();
      } finally {
        client.close();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });
  });
}

class FakeMultiStreamTelegram extends TelegramService {
  final Map<String, Uint8List> files = {};

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
    CancelToken? cancelToken,
  ]) => downloadByFileIdWithProgress(fileId, priority: priority, cancelToken: cancelToken);

  @override
  Future<Uint8List> downloadByFileIdWithProgress(
    String fileId, {
    RequestPriority priority = RequestPriority.normal,
    void Function(int count, int total)? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    final data = files[fileId];
    if (data != null) {
      onReceiveProgress?.call(data.length, data.length);
      return data;
    }
    throw Exception('File not found in fake telegram: $fileId');
  }

  @override
  Future<Stream<List<int>>> streamByFileId(
    String fileId, {
    RequestPriority priority = RequestPriority.normal,
    int? startByte,
    int? endByte,
    CancelToken? cancelToken,
  }) async {
    final data = await downloadByFileId(fileId, priority, cancelToken);
    final start = startByte ?? 0;
    final end = (endByte != null && endByte + 1 < data.length) ? endByte + 1 : data.length;
    return Stream.value(data.sublist(start, end));
  }
}
