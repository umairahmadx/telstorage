/*
 * File: video_stream_server_test.dart
 * Description: Unit tests for VideoStreamServer verifying byte mapping, Range header parsing, loopback HTTP serving, and chunk deduplication.
 */

import 'dart:convert';
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
    tempDir = await Directory.systemTemp.createTemp('vss_test_');
    VideoChunkCacheManager.instance.setBaseDirForTesting(tempDir);
    server = VideoStreamServer.instance;
  });

  tearDown(() async {
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
  });
}
