/*
 * File: video_stream_multi_chunk_test.dart
 * Description: Unit and integration tests for multi-chunk raw video streaming, HEAD probing, MIME resolution, and cross-boundary slicing.
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

  group('MIME Resolution & Math Unit Tests', () {
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

        final req = await client.headUrl(Uri.parse(streamUrl));
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.ok));
        expect(res.contentLength, equals(payload.length));
        expect(res.headers.value(HttpHeaders.acceptRangesHeader), equals('bytes'));
        final body = await res.fold<List<int>>([], (p, e) => p..addAll(e));
        expect(body, isEmpty);

        final req2 = await client.headUrl(Uri.parse(streamUrl));
        req2.headers.set(HttpHeaders.rangeHeader, 'bytes=10-29');
        final res2 = await req2.close();
        expect(res2.statusCode, equals(HttpStatus.partialContent));
        expect(res2.contentLength, equals(20));
        expect(res2.headers.value(HttpHeaders.contentRangeHeader), equals('bytes 10-29/${payload.length}'));
        final body2 = await res2.fold<List<int>>([], (p, e) => p..addAll(e));
        expect(body2, isEmpty);
      } finally {
        client.close();
      }
    });

    test('Multi-chunk raw stream slices exact video bytes across part boundaries', () async {
      final rawVideo = Uint8List.fromList(List.generate(5000, (i) => (i * 7) % 256));
      const filename = 'camera_vid.mp4';
      const partSize = 3000;

      final chunk0 = Uint8List.sublistView(rawVideo, 0, partSize);
      final chunk1 = Uint8List.sublistView(rawVideo, partSize);

      final testRecord = FileRecord(
        fileId: 'raw_multi_vid_123',
        name: filename,
        metadataMessageId: 85,
        metadataFileId: 'raw_meta_id',
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
          {'index': 1, 'message_id': 86, 'file_id': 'tg_raw_chunk_1', 'size_mb': 1.0, 'part_name': 'camera_vid.mp4.001'},
          {'index': 2, 'message_id': 87, 'file_id': 'tg_raw_chunk_2', 'size_mb': 1.0, 'part_name': 'camera_vid.mp4.002'},
        ],
      });

      final fakeTelegram = FakeMultiStreamTelegram();
      fakeTelegram.files['raw_meta_id'] = Uint8List.fromList(utf8.encode(metadataJson));
      fakeTelegram.files['tg_raw_chunk_1'] = chunk0;
      fakeTelegram.files['tg_raw_chunk_2'] = chunk1;

      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);

      server.registerFile(testRecord);
      server.setChunkFetcherForTesting(null);
      server.setPartSizeForTesting(partSize);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);

        // Cross-chunk boundary range (chunk 0 -> chunk 1)
        final req = await client.getUrl(Uri.parse(streamUrl));
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=2800-3200');
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.partialContent));
        expect(res.contentLength, equals(401));
        final received = await res.fold<List<int>>([], (p, e) => p..addAll(e));
        expect(received, equals(rawVideo.sublist(2800, 3201)));

        // EOF range: bytes 4900 to 4999 (last 100 bytes)
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

    test('Multi-chunk raw full un-ranged GET returns exact video payload', () async {
      final rawVideo = Uint8List.fromList(List.generate(4000, (i) => (i * 3) % 256));
      const filename = 'full_get_vid.mp4';
      const partSize = 2500;

      final chunk0 = Uint8List.sublistView(rawVideo, 0, partSize);
      final chunk1 = Uint8List.sublistView(rawVideo, partSize);

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
        'file_id': testRecord.fileId,
        'name': testRecord.name,
        'size_mb': testRecord.sizeMb,
        'chunk_count': 2,
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

    test('Arbitrary seek to intermediate chunk only requests that chunk', () async {
      final rawVideo = Uint8List.fromList(List.generate(9000, (i) => (i * 5) % 256));
      const filename = 'seek_vid.mp4';
      const partSize = 3000; // 3 chunks of 3000 bytes: [0..2999], [3000..5999], [6000..8999]

      final requestedChunks = <int>[];

      final testRecord = FileRecord(
        fileId: 'seek_test_vid',
        name: filename,
        metadataMessageId: 120,
        metadataFileId: 'seek_meta_id',
        sizeMb: rawVideo.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 3,
        sha256Hash: 'dummy_seek',
      );

      final metaJson = jsonEncode({
        'file_id': testRecord.fileId,
        'name': testRecord.name,
        'size_mb': testRecord.sizeMb,
        'chunk_count': 3,
        'chunks': [
          {'index': 1, 'message_id': 121, 'file_id': 's_c1', 'size_mb': 1.0},
          {'index': 2, 'message_id': 122, 'file_id': 's_c2', 'size_mb': 1.0},
          {'index': 3, 'message_id': 123, 'file_id': 's_c3', 'size_mb': 1.0},
        ],
      });

      final fakeTelegram = FakeMultiStreamTelegram();
      fakeTelegram.files['seek_meta_id'] = Uint8List.fromList(utf8.encode(metaJson));
      fakeTelegram.files['s_c1'] = Uint8List.sublistView(rawVideo, 0, 3000);
      fakeTelegram.files['s_c2'] = Uint8List.sublistView(rawVideo, 3000, 6000);
      fakeTelegram.files['s_c3'] = Uint8List.sublistView(rawVideo, 6000, 9000);

      fakeTelegram.onDownload = (fileId) {
        if (fileId == 's_c1') requestedChunks.add(0);
        if (fileId == 's_c2') requestedChunks.add(1);
        if (fileId == 's_c3') requestedChunks.add(2);
      };

      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);
      server.registerFile(testRecord);
      server.setChunkFetcherForTesting(null);
      server.setPartSizeForTesting(partSize);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId, testRecord.name);

        // Seek directly to chunk 2 (bytes 6500-7000)
        final req = await client.getUrl(Uri.parse(streamUrl));
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=6500-7000');
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.partialContent));
        expect(res.contentLength, equals(501));
        final received = await res.fold<List<int>>([], (p, e) => p..addAll(e));
        expect(received, equals(rawVideo.sublist(6500, 7001)));

        // Verify chunk 0 was NEVER downloaded or decoded
        expect(requestedChunks.contains(0), isFalse);
        expect(requestedChunks.contains(2), isTrue);
      } finally {
        client.close();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });
  });
}

class FakeMultiStreamTelegram extends TelegramService {
  final Map<String, Uint8List> files = {};
  void Function(String fileId)? onDownload;

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
    onDownload?.call(fileId);
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
