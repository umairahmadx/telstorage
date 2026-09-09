/*
 * File: video_stream_server_test.dart
 * Description: Unit tests for VideoStreamServer verifying byte mapping, Range header parsing, loopback HTTP serving, and chunk deduplication.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/video_chunk_cache_manager.dart';
import 'package:telstorage/core/services/video_stream_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoStreamServer server;
  late Directory tempDir;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('vss_test_');
    VideoChunkCacheManager.instance.setBaseDirForTesting(tempDir);
    server = VideoStreamServer.instance;
  });

  tearDown(() async {
    server.setFileRecordProviderForTesting(null);
    server.setChunkFetcherForTesting(null);
    VideoChunkCacheManager.instance.setBaseDirForTesting(null);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    await server.stop();
  });

  group('VideoStreamServer Math & Range Unit Tests', () {
    test('TC-VSS-01: calculateHeaderOffset calculates 0 for uncompressed and 30+nameLen for ZIP STORE', () {
      expect(VideoStreamServer.calculateHeaderOffset('video.mp4', isZipped: false), equals(0));

      const filename = 'test_clip.mp4';
      final expectedOffset = 30 + utf8.encode(filename).length;
      expect(
        VideoStreamServer.calculateHeaderOffset(filename, isZipped: true),
        equals(expectedOffset),
      );
    });

    test('TC-VSS-02: mapByteToChunk correctly computes chunk index and offset', () {
      const partSize = 1000;
      const headerOffset = 40;

      // Video byte 0 -> ZIP byte 40 -> Chunk 0, offset 40
      final map0 = VideoStreamServer.mapByteToChunk(
        videoByteOffset: 0,
        headerOffset: headerOffset,
        partSize: partSize,
      );
      expect(map0.chunkIndex, equals(0));
      expect(map0.chunkOffset, equals(40));

      // Video byte 959 -> ZIP byte 999 -> Chunk 0, offset 999
      final map959 = VideoStreamServer.mapByteToChunk(
        videoByteOffset: 959,
        headerOffset: headerOffset,
        partSize: partSize,
      );
      expect(map959.chunkIndex, equals(0));
      expect(map959.chunkOffset, equals(999));

      // Video byte 960 -> ZIP byte 1000 -> Chunk 1, offset 0
      final map960 = VideoStreamServer.mapByteToChunk(
        videoByteOffset: 960,
        headerOffset: headerOffset,
        partSize: partSize,
      );
      expect(map960.chunkIndex, equals(1));
      expect(map960.chunkOffset, equals(0));
    });

    test('TC-VSS-03: parseByteRange parses various RFC 7233 range expressions', () {
      const totalSize = 5000;

      // bytes=0-1023
      final r1 = VideoStreamServer.parseByteRange('bytes=0-1023', totalSize);
      expect(r1, isNotNull);
      expect(r1!.start, equals(0));
      expect(r1.end, equals(1023));

      // bytes=1000-
      final r2 = VideoStreamServer.parseByteRange('bytes=1000-', totalSize);
      expect(r2, isNotNull);
      expect(r2!.start, equals(1000));
      expect(r2.end, equals(4999));

      // bytes=-500 (suffix range)
      final r3 = VideoStreamServer.parseByteRange('bytes=-500', totalSize);
      expect(r3, isNotNull);
      expect(r3!.start, equals(4500));
      expect(r3.end, equals(4999));

      // null range -> entire file
      final r4 = VideoStreamServer.parseByteRange(null, totalSize);
      expect(r4, isNotNull);
      expect(r4!.start, equals(0));
      expect(r4.end, equals(4999));

      // Out of bounds start -> invalid
      final r5 = VideoStreamServer.parseByteRange('bytes=6000-7000', totalSize);
      expect(r5, isNull);

      // Single byte range: bytes=0-0
      final r6 = VideoStreamServer.parseByteRange('bytes=0-0', totalSize);
      expect(r6, isNotNull);
      expect(r6!.start, equals(0));
      expect(r6.end, equals(0));
      expect(r6.length, equals(1));

      // Inverted bounds start > end -> invalid
      final r7 = VideoStreamServer.parseByteRange('bytes=100-50', totalSize);
      expect(r7, isNull);

      // Malformed non-numeric -> invalid
      final r8 = VideoStreamServer.parseByteRange('bytes=abc', totalSize);
      expect(r8, isNull);

      // Multiple comma-separated ranges -> unsupported, returns null (416)
      final r9 = VideoStreamServer.parseByteRange('bytes=0-10,20-30', totalSize);
      expect(r9, isNull);
    });
  });

  group('VideoStreamServer Loopback HTTP Integration Tests', () {
    test('TC-VSS-04: serves HTTP 206 Partial Content for byte range over loopback', () async {
      final sampleVideoData = Uint8List.fromList(List.generate(200, (i) => i % 256));
      final testRecord = FileRecord(
        fileId: 'stream_test_vid_1',
        name: 'test.mp4',
        metadataMessageId: 10,
        sizeMb: sampleVideoData.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy',
      );

      server.setFileRecordProviderForTesting((fileId) async {
        if (fileId == testRecord.fileId) return testRecord;
        return null;
      });

      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async {
        return sampleVideoData;
      });

      final port = await server.start();
      expect(port, greaterThan(0));

      final streamUrl = server.getStreamUrl(testRecord.fileId);
      expect(streamUrl, contains('http://127.0.0.1:$port/stream/${testRecord.fileId}'));

      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(streamUrl));
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=20-39');
        final response = await request.close();

        expect(response.statusCode, equals(HttpStatus.partialContent));
        expect(response.headers.value(HttpHeaders.acceptRangesHeader), equals('bytes'));
        expect(response.headers.value(HttpHeaders.contentRangeHeader), equals('bytes 20-39/200'));
        expect(response.contentLength, equals(20));

        final responseBytes = await response.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        final expectedBytes = sampleVideoData.sublist(20, 40);
        expect(responseBytes, equals(expectedBytes));
      } finally {
        client.close();
      }
    });

    test('TC-VSS-05: returns HTTP 416 for invalid range', () async {
      final sampleVideoData = Uint8List(100);
      final testRecord = FileRecord(
        fileId: 'stream_test_vid_2',
        name: 'test2.mp4',
        metadataMessageId: 11,
        sizeMb: 100 / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy2',
      );

      server.setFileRecordProviderForTesting((fileId) async => testRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => sampleVideoData);

      await server.start();
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(server.getStreamUrl(testRecord.fileId)));
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=500-600');
        final response = await request.close();

        expect(response.statusCode, equals(HttpStatus.requestedRangeNotSatisfiable));
        expect(response.headers.value(HttpHeaders.contentRangeHeader), equals('bytes */100'));
      } finally {
        client.close();
      }
    });

    test('TC-VSS-06: serves HTTP 200 OK for un-ranged GET requests per RFC 7233', () async {
      final sampleVideoData = Uint8List.fromList(List.generate(50, (i) => i));
      final testRecord = FileRecord(
        fileId: 'stream_test_vid_3',
        name: 'test3.mp4',
        metadataMessageId: 12,
        sizeMb: sampleVideoData.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy3',
      );

      server.setFileRecordProviderForTesting((fileId) async => testRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => sampleVideoData);

      await server.start();
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(server.getStreamUrl(testRecord.fileId)));
        // Note: No Range header set
        final response = await request.close();

        expect(response.statusCode, equals(HttpStatus.ok));
        expect(response.headers.value(HttpHeaders.acceptRangesHeader), equals('bytes'));
        expect(response.headers.value(HttpHeaders.contentRangeHeader), isNull);
        expect(response.contentLength, equals(50));
      } finally {
        client.close();
      }
    });

    test('TC-VSS-07: in-memory registerFile resolves FileRecord without provider and unregisters cleanly', () async {
      final sampleVideoData = Uint8List.fromList(List.generate(64, (i) => 255 - i));
      final testRecord = FileRecord(
        fileId: 'stream_test_vid_mem_1',
        name: 'mem_video.mp4',
        metadataMessageId: 20,
        sizeMb: sampleVideoData.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_mem',
      );

      // Do NOT set provider — register in-memory instead
      server.registerFile(testRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => sampleVideoData);

      final port = await server.start();
      expect(port, greaterThan(0));
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);
        expect(streamUrl, contains('/stream/${testRecord.fileId}/mem_video.mp4'));

        final request = await client.getUrl(Uri.parse(streamUrl));
        final response = await request.close();
        expect(response.statusCode, equals(HttpStatus.ok));
        expect(response.contentLength, equals(64));
        await response.drain();

        // Now unregister
        server.unregisterFile(testRecord.fileId);
        final reqAfterUnregister = await client.getUrl(Uri.parse(streamUrl));
        final resAfterUnregister = await reqAfterUnregister.close();
        expect(resAfterUnregister.statusCode, equals(HttpStatus.notFound));
        await resAfterUnregister.drain();
      } finally {
        client.close();
      }
    });

    test('TC-VSS-08: resolves 1-based chunks from Telegram metadata JSON without throwing Chunk 0 not found', () async {
      final chunkBytes = Uint8List.fromList(List.generate(100, (i) => i * 2));
      final testRecord = FileRecord(
        fileId: 'stream_vid_meta_1',
        name: 'movie.mp4',
        metadataMessageId: 30,
        metadataFileId: 'meta_json_file_id',
        sizeMb: chunkBytes.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_sha',
      );

      // 1-based chunk metadata as produced by upload_service.dart
      final metadataJson = jsonEncode({
        'file_id': testRecord.fileId,
        'name': testRecord.name,
        'size_mb': testRecord.sizeMb,
        'chunk_count': 1,
        'chunks': [
          {
            'index': 1, // 1-based index!
            'message_id': 31,
            'file_id': 'tg_chunk_file_001',
            'size_mb': testRecord.sizeMb,
            'part_name': 'movie.mp4',
          }
        ],
      });

      final fakeTelegram = FakeStreamTelegramService();
      fakeTelegram.files['meta_json_file_id'] = Uint8List.fromList(utf8.encode(metadataJson));
      fakeTelegram.files['tg_chunk_file_001'] = chunkBytes;

      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);

      server.registerFile(testRecord);
      // Remove mock chunk fetcher to execute real _executeChunkFetch logic
      server.setChunkFetcherForTesting(null);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);
        final request = await client.getUrl(Uri.parse(streamUrl));
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-49');
        final response = await request.close();

        expect(response.statusCode, equals(HttpStatus.partialContent));
        expect(response.contentLength, equals(50));

        final responseBytes = await response.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(responseBytes, equals(chunkBytes.sublist(0, 50)));

        // Verify metadata was downloaded once and subsequent range uses cached metadata and disk cache
        final secondRequest = await client.getUrl(Uri.parse(streamUrl));
        secondRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=50-99');
        final secondResponse = await secondRequest.close();
        expect(secondResponse.statusCode, equals(HttpStatus.partialContent));
        final secondBytes = await secondResponse.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(secondBytes, equals(chunkBytes.sublist(50, 100)));

        // 1 call for metadata, 1 call for chunk data (2nd range served from local VideoChunkCacheManager!)
        expect(fakeTelegram.downloadCallCount, equals(2));
      } finally {
        client.close();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });


    test('TC-VSS-11: safe URL routing with encoded/opaque file IDs and route boundary rejection', () async {
      final sampleVideoData = Uint8List.fromList(List.generate(32, (i) => i));
      const opaqueFileId = 'tg_file:special/id+123';
      final testRecord = FileRecord(
        fileId: opaqueFileId,
        name: 'video with spaces & emoji 🎬.mp4',
        metadataMessageId: 60,
        sizeMb: sampleVideoData.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_opaque',
      );

      server.registerFile(testRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => sampleVideoData);

      final port = await server.start();
      expect(port, greaterThan(0));
      final client = HttpClient();
      try {
        // Stream URL should encode opaque fileId and unicode filename safely
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);
        final request = await client.getUrl(Uri.parse(streamUrl));
        final response = await request.close();
        expect(response.statusCode, equals(HttpStatus.ok));
        expect(response.contentLength, equals(32));
        await response.drain();

        // More than 3 segments -> 404
        final invalidUrl = 'http://127.0.0.1:$port/stream/file_1/extra/segment/here';
        final reqInvalid = await client.getUrl(Uri.parse(invalidUrl));
        final resInvalid = await reqInvalid.close();
        expect(resInvalid.statusCode, equals(HttpStatus.notFound));
        await resInvalid.drain();
      } finally {
        client.close();
      }
    });

    test('TC-VSS-12: resolves legacy 0-based chunks from metadata fallback', () async {
      final chunkBytes = Uint8List.fromList(List.generate(60, (i) => i));
      final testRecord = FileRecord(
        fileId: 'stream_vid_legacy_0',
        name: 'legacy.mp4',
        metadataMessageId: 70,
        metadataFileId: 'legacy_meta_file_id',
        sizeMb: chunkBytes.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_legacy',
      );

      final metadataJson = jsonEncode({
        'file_id': testRecord.fileId,
        'name': testRecord.name,
        'size_mb': testRecord.sizeMb,
        'chunk_count': 1,
        'chunks': [
          {
            'index': 0,
            'message_id': 71,
            'file_id': 'tg_chunk_legacy_000',
            'size_mb': testRecord.sizeMb,
            'part_name': 'legacy.mp4',
          }
        ],
      });

      final fakeTelegram = FakeStreamTelegramService();
      fakeTelegram.files['legacy_meta_file_id'] = Uint8List.fromList(utf8.encode(metadataJson));
      fakeTelegram.files['tg_chunk_legacy_000'] = chunkBytes;

      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);

      server.registerFile(testRecord);
      server.setChunkFetcherForTesting(null);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);
        final request = await client.getUrl(Uri.parse(streamUrl));
        final response = await request.close();

        expect(response.statusCode, equals(HttpStatus.ok));
        expect(response.contentLength, equals(60));
        final responseBytes = await response.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(responseBytes, equals(chunkBytes));
      } finally {
        client.close();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });
  });
}

class FakeStreamTelegramService extends TelegramService {
  final Map<String, Uint8List> files = {};
  int downloadCallCount = 0;

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
  ]) async {
    downloadCallCount++;
    final data = files[fileId];
    if (data != null) return data;
    throw Exception('File not found in fake telegram: $fileId');
  }
}

