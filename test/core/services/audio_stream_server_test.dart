/*
 * File: audio_stream_server_test.dart
 * Description: Unit tests for loopback audio streaming via VideoStreamServer verifying MIME resolution, RFC 7233 byte range parsing, and HTTP 206 responses.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
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
    tempDir = await Directory.systemTemp.createTemp('audio_vss_test_');
    VideoChunkCacheManager.instance.setBaseDirForTesting(tempDir);
    server = VideoStreamServer.instance;
  });

  tearDown(() async {
    await server.stop();
    server.setFileRecordProviderForTesting(null);
    server.setChunkFetcherForTesting(null);
    VideoChunkCacheManager.instance.setBaseDirForTesting(null);
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('VideoStreamServer Audio MIME Resolution Unit Tests', () {
    test('TC-ASS-01: resolveMimeType accurately identifies audio formats', () {
      expect(VideoStreamServer.resolveMimeType('song.mp3', null), equals('audio/mpeg'));
      expect(VideoStreamServer.resolveMimeType('track.m4a', null), equals('audio/mp4'));
      expect(VideoStreamServer.resolveMimeType('voice.aac', null), equals('audio/mp4'));
      expect(VideoStreamServer.resolveMimeType('audio.flac', null), equals('audio/flac'));
      expect(VideoStreamServer.resolveMimeType('sound.ogg', null), equals('audio/ogg'));
      expect(VideoStreamServer.resolveMimeType('recording.wav', null), equals('audio/wav'));
      expect(VideoStreamServer.resolveMimeType('podcast.opus', null), equals('audio/ogg'));
    });

    test('TC-ASS-02: explicit non-octet-stream MIME in record takes precedence', () {
      expect(
        VideoStreamServer.resolveMimeType('test.mp3', 'audio/x-custom'),
        equals('audio/x-custom'),
      );
    });

    test('TC-ASS-03: fallback to video/mp4 for unrecognized file extensions', () {
      expect(
        VideoStreamServer.resolveMimeType('unknown_media.xyz', null),
        equals('video/mp4'),
      );
    });
  });

  group('VideoStreamServer Audio HTTP 206 Streaming Tests', () {
    test('TC-ASS-04: loopback server serves audio byte range with HTTP 206', () async {
      final dio = Dio();
      final port = await server.start();
      expect(port, greaterThan(0));

      final chunkData = Uint8List.fromList(List.generate(5000, (i) => i % 256));

      final audioRecord = FileRecord(
        fileId: 'audio_123',
        name: 'track.mp3',
        metadataMessageId: 101,
        sizeMb: 5000 / (1024 * 1024),
        mimeType: 'audio/mpeg',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'dummy_hash',
      );

      server.setFileRecordProviderForTesting((fileId) async => audioRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => chunkData);

      final reg = server.registerFile(audioRecord);
      try {
        final streamUrl = server.getStreamUrl('audio_123', 'track.mp3');

        final res = await dio.get<List<int>>(
          streamUrl,
          options: Options(
            headers: {'Range': 'bytes=100-199'},
            responseType: ResponseType.bytes,
            validateStatus: (status) => status == 206,
          ),
        );

        expect(res.statusCode, equals(206));
        expect(res.headers.value('Content-Range'), equals('bytes 100-199/5000'));
        expect(res.headers.value('Content-Type'), equals('audio/mpeg'));
        expect(res.data?.length, equals(100));
        expect(res.data, equals(chunkData.sublist(100, 200)));
      } finally {
        reg.dispose();
      }
    });

    test('TC-ASS-05: full audio stream request returns HTTP 200 without Range header', () async {
      final dio = Dio();
      await server.start();

      final chunkData = Uint8List.fromList(utf8.encode('ID3_AUDIO_HEADER_STREAM_DATA'));

      final audioRecord = FileRecord(
        fileId: 'audio_456',
        name: 'intro.wav',
        metadataMessageId: 102,
        sizeMb: chunkData.length / (1024 * 1024),
        mimeType: 'audio/wav',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'dummy_hash_2',
      );

      server.setFileRecordProviderForTesting((fileId) async => audioRecord);
      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => chunkData);

      final reg = server.registerFile(audioRecord);
      try {
        final streamUrl = server.getStreamUrl('audio_456', 'intro.wav');

        final res = await dio.get<List<int>>(
          streamUrl,
          options: Options(
            responseType: ResponseType.bytes,
            validateStatus: (status) => status == 200,
          ),
        );

        expect(res.statusCode, equals(200));
        expect(res.headers.value('Content-Length'), equals('${chunkData.length}'));
        expect(res.headers.value('Content-Type'), equals('audio/wav'));
        expect(res.data, equals(chunkData));
      } finally {
        reg.dispose();
      }
    });
  });
}
