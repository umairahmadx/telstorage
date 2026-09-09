/*
 * File: video_stream_edge_cases_test.dart
 * Description: Adversarial unit tests for VideoStreamServer covering RFC 9110 range clamping, URI decoding, registration handles, and preflight failures.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/video_chunk_cache_manager.dart';
import 'package:telstorage/core/services/video_stream_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoStreamServer server;
  late Directory tempDir;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('vss_edge_test_');
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

  group('VideoStreamServer Edge Cases & Wire Behavior Tests', () {
    test('TC-VSS-EC01: getStreamUrl before start() throws StateError', () {
      expect(
        () => server.getStreamUrl('test_file_id'),
        throwsA(isA<StateError>()),
      );
    });

    test('TC-VSS-EC02: Literal percent and encoded percent in fileId resolve safely without double decode', () async {
      final sampleData = Uint8List.fromList(List.generate(20, (i) => i));
      const literalPercentId = 'video%20test%literal';
      final testRecord = FileRecord(
        fileId: literalPercentId,
        name: 'test.mp4',
        metadataMessageId: 10,
        sizeMb: sampleData.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_literal',
      );

      final registration = server.registerFile(testRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async {
        expect(fileId, equals(literalPercentId));
        return sampleData;
      });

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);
        final request = await client.getUrl(Uri.parse(streamUrl));
        final response = await request.close();
        expect(response.statusCode, equals(HttpStatus.ok));
        final bytes = await response.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(bytes, equals(sampleData));
      } finally {
        client.close();
        registration.dispose();
      }
    });

    test('TC-VSS-EC03: Case-insensitive Range header (Bytes=) returns 206 Partial Content', () async {
      final sampleData = Uint8List.fromList(List.generate(50, (i) => i));
      final testRecord = FileRecord(
        fileId: 'case_range_vid_1',
        name: 'case.mp4',
        metadataMessageId: 11,
        sizeMb: sampleData.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_case',
      );

      final registration = server.registerFile(testRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => sampleData);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId);
        final request = await client.getUrl(Uri.parse(streamUrl));
        request.headers.set(HttpHeaders.rangeHeader, 'Bytes=0-9');
        final response = await request.close();
        expect(response.statusCode, equals(HttpStatus.partialContent));
        expect(response.headers.value(HttpHeaders.contentRangeHeader), equals('bytes 0-9/50'));
        expect(response.contentLength, equals(10));
        final bytes = await response.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(bytes, equals(sampleData.sublist(0, 10)));
      } finally {
        client.close();
        registration.dispose();
      }
    });

    test('TC-VSS-EC04: Clamped range (bytes=0-999 on 50-byte file) returns 206 bytes 0-49/50', () async {
      final sampleData = Uint8List.fromList(List.generate(50, (i) => i));
      final testRecord = FileRecord(
        fileId: 'clamp_vid_1',
        name: 'clamp.mp4',
        metadataMessageId: 12,
        sizeMb: sampleData.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_clamp',
      );

      final registration = server.registerFile(testRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => sampleData);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId);
        final request = await client.getUrl(Uri.parse(streamUrl));
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-999');
        final response = await request.close();
        expect(response.statusCode, equals(HttpStatus.partialContent));
        expect(response.headers.value(HttpHeaders.contentRangeHeader), equals('bytes 0-49/50'));
        expect(response.contentLength, equals(50));
        final bytes = await response.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
        expect(bytes, equals(sampleData));
      } finally {
        client.close();
        registration.dispose();
      }
    });

    test('TC-VSS-EC05: Multi-range request returns 416 with Content-Range: bytes */total', () async {
      final sampleData = Uint8List.fromList(List.generate(50, (i) => i));
      final testRecord = FileRecord(
        fileId: 'multi_range_vid_1',
        name: 'multi.mp4',
        metadataMessageId: 13,
        sizeMb: sampleData.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_multi',
      );

      final registration = server.registerFile(testRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => sampleData);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId);
        final request = await client.getUrl(Uri.parse(streamUrl));
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-10, 20-30');
        final response = await request.close();
        expect(response.statusCode, equals(HttpStatus.requestedRangeNotSatisfiable));
        expect(response.headers.value(HttpHeaders.contentRangeHeader), equals('bytes */50'));
        expect(response.contentLength, equals(0));
        await response.drain();
      } finally {
        client.close();
        registration.dispose();
      }
    });

    test('TC-VSS-EC06: StreamRegistration handle disposal decrements refCount and unregisters', () async {
      final sampleData = Uint8List.fromList(List.generate(30, (i) => i));
      final testRecord = FileRecord(
        fileId: 'handle_vid_1',
        name: 'handle.mp4',
        metadataMessageId: 14,
        sizeMb: sampleData.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_handle',
      );

      final reg1 = server.registerFile(testRecord);
      final reg2 = server.registerFile(testRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => sampleData);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId);

        // Both handles active -> serves 200
        final req1 = await client.getUrl(Uri.parse(streamUrl));
        final res1 = await req1.close();
        expect(res1.statusCode, equals(HttpStatus.ok));
        await res1.drain();

        // Dispose first handle -> still serves 200 because reg2 is active
        reg1.dispose();
        final req2 = await client.getUrl(Uri.parse(streamUrl));
        final res2 = await req2.close();
        expect(res2.statusCode, equals(HttpStatus.ok));
        await res2.drain();

        // Disposing reg1 again is idempotent
        reg1.dispose();

        // Dispose second handle -> now unregisters completely -> 404
        reg2.dispose();
        final req3 = await client.getUrl(Uri.parse(streamUrl));
        final res3 = await req3.close();
        expect(res3.statusCode, equals(HttpStatus.notFound));
        await res3.drain();
      } finally {
        client.close();
      }
    });

    test('TC-VSS-EC07: Conflicting registration with different metadata or chunkCount throws ArgumentError', () {
      final recordA = FileRecord(
        fileId: 'conflict_vid_1',
        name: 'a.mp4',
        metadataMessageId: 15,
        metadataFileId: 'meta_a',
        sizeMb: 10,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: 'dummy_a',
      );

      final recordB = FileRecord(
        fileId: 'conflict_vid_1',
        name: 'b.mp4',
        metadataMessageId: 16,
        metadataFileId: 'meta_b', // Conflicting metadata!
        sizeMb: 10,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: 'dummy_b',
      );

      final reg = server.registerFile(recordA);
      try {
        expect(() => server.registerFile(recordB), throwsA(isA<ArgumentError>()));
      } finally {
        reg.dispose();
      }
    });
  });
}
