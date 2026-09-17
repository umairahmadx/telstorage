/*
 * File: thumbnail_and_video_stream_sync_test.dart
 * Description: Rule 10 Automated Reproduction Tests (RED) for image thumbnail generation on disk file paths, video streaming prefetch anchor & chunk change notifications, and cache reactivity.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/video_chunk_cache_manager.dart';
import 'package:telstorage/core/services/video_stream_pipeliner.dart';
import 'package:telstorage/core/services/video_stream_server.dart';
import 'package:telstorage/core/utils/thumbnail_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('thumb_video_sync_test_');
    VideoChunkCacheManager.instance.setBaseDirForTesting(tempDir);
  });

  tearDown(() async {
    VideoStreamServer.instance.setChunkFetcherForTesting(null);
    VideoStreamServer.instance.setFileRecordProviderForTesting(null);
    VideoStreamServer.instance.prefetchCoordinator.setDownloaderForTesting(null);
    ServiceLocator.instance.setInitializedForTesting(false);
    VideoChunkCacheManager.instance.setBaseDirForTesting(null);
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('Bug Reproduction Tests (RED)', () {
    test(
        'REPRODUCTION 1: ThumbnailGenerator.generate generates thumbnail for image file when bytes is null and filePath is provided',
        () async {
      // Create a valid JPEG file on disk
      final sampleImg = img.Image(width: 300, height: 200);
      img.fill(sampleImg, color: img.ColorRgba8(200, 50, 50, 255));
      final sampleJpgBytes = Uint8List.fromList(img.encodeJpg(sampleImg));
      final imageFile = File('${tempDir.path}/sample.jpg');
      await imageFile.writeAsBytes(sampleJpgBytes, flush: true);

      // Call generate with filePath and bytes: null (normal upload from disk)
      final result = await ThumbnailGenerator.generate(
        filePath: imageFile.path,
        filename: 'sample.jpg',
        mimeType: 'image/jpeg',
      );

      // In current code: returns null because 'else if (bytes != null)' skips images if bytes is null
      expect(result, isNotNull,
          reason:
              'ThumbnailGenerator should read bytes from filePath when bytes is null');
      expect(result?.bytes, isNotNull);
      expect(result?.extension, equals('jpg'));
    });

    test(
        'REPRODUCTION 2: VideoStreamPipeliner notifies chunkChangeNotifier when a chunk is committed to disk',
        () async {
      final pipeliner = VideoStreamPipeliner();
      final record = FileRecord(
        fileId: 'pipeliner_test_file',
        name: 'test.mp4',
        sizeMb: 50.0,
        uploadedAt: DateTime.now(),
        mimeType: 'video/mp4',
        chunkCount: 3,
        metadataMessageId: 1,
        sha256Hash: 'hash',
        metadataFileId: 'meta_file',
      );

      final chunkData = Uint8List.fromList(List.generate(1024, (i) => i % 256));
      pipeliner.setStreamFetcherForTesting((fileId, chunkIndex) async* {
        yield chunkData;
      });

      final initialChangeCount =
          VideoChunkCacheManager.instance.chunkChangeNotifier.value;

      final controller = StreamController<List<int>>();
      final streamFuture = controller.stream.drain<void>();

      await pipeliner.pipeChunkRange(
        record: record,
        chunkIndex: 0,
        sliceStart: 0,
        sliceEnd: 1024,
        output: controller,
      );
      await controller.close();
      await streamFuture;

      // In current code: chunkChangeNotifier.value is NOT incremented by pipeliner
      expect(
        VideoChunkCacheManager.instance.chunkChangeNotifier.value,
        greaterThan(initialChangeCount),
        reason:
            'VideoStreamPipeliner must increment chunkChangeNotifier when saving chunk to disk',
      );
    });

    test(
        'REPRODUCTION 3: VideoStreamServer onChunkRequested anchors prefetch to startChunk (not endChunk)',
        () async {
      final server = VideoStreamServer.instance;
      server.setPartSizeForTesting(1000);

      final record = FileRecord(
        fileId: 'vss_prefetch_anchor_test',
        name: 'test_vid.mp4',
        sizeMb: 0.003, // ~3000 bytes -> 3 parts of 1000 bytes
        uploadedAt: DateTime.now(),
        mimeType: 'video/mp4',
        chunkCount: 3,
        metadataMessageId: 1,
        sha256Hash: 'hash',
        metadataFileId: 'meta_file',
      );

      final fakeTelegram = FakeStreamTelegramService();
      final metadataJson = jsonEncode({
        'chunk_count': 3,
        'chunks': [
          {'index': 1, 'file_id': 'f1', 'message_id': 1, 'size_mb': 0.001},
          {'index': 2, 'file_id': 'f2', 'message_id': 2, 'size_mb': 0.001},
          {'index': 3, 'file_id': 'f3', 'message_id': 3, 'size_mb': 0.001},
        ],
      });
      fakeTelegram.files['meta_file'] = Uint8List.fromList(utf8.encode(metadataJson));
      fakeTelegram.files['f1'] = Uint8List(1000);
      fakeTelegram.files['f2'] = Uint8List(1000);
      fakeTelegram.files['f3'] = Uint8List(1000);
      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);

      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async {
        return Uint8List(1000);
      });

      final prefetchedChunks = <int>[];
      server.prefetchCoordinator.setDownloaderForTesting(
          (rec, chunkIdx, priority) async {
        prefetchedChunks.add(chunkIdx);
        return Uint8List(1000);
      });

      server.setFileRecordProviderForTesting((fileId) async => record);
      server.registerFile(record);

      final port = await server.start();
      final client = HttpClient();

      // Request beginning of video: bytes 0-500 (in chunk 0)
      final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/stream/${record.fileId}/test_vid.mp4'));
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-500');
      final resp = await req.close();
      await resp.drain<void>();
      client.close();

      Future<void>? workerFuture;
      for (int i = 0; i < 100; i++) {
        workerFuture = server.prefetchCoordinator.waitForWorkerForTesting(record.fileId);
        if (workerFuture != null) break;
        await Future.delayed(const Duration(milliseconds: 20));
      }
      if (workerFuture != null) {
        await workerFuture.timeout(const Duration(seconds: 3));
      } else {
        for (int i = 0; i < 50; i++) {
          if (prefetchedChunks.contains(1)) break;
          await Future.delayed(const Duration(milliseconds: 20));
        }
      }

      // When starting chunk 0, chunks 1 and 2 should be prefetched
      // In current code: endChunk (2) was passed instead of startChunk (0),
      // so prefetchedChunks was empty because target > maxChunk!
      expect(prefetchedChunks, contains(1),
          reason:
              'Prefetcher should prefetch chunk 1 when playback is at chunk 0');

      await server.stop();
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

  @override
  Future<Stream<List<int>>> streamByFileId(
    String fileId, {
    RequestPriority priority = RequestPriority.immediate,
    int? startByte,
    int? endByte,
    CancelToken? cancelToken,
  }) async {
    final data = await downloadByFileId(fileId, priority);
    final start = startByte ?? 0;
    final end = (endByte != null && endByte + 1 < data.length) ? endByte + 1 : data.length;
    return Stream.value(data.sublist(start, end));
  }
}
