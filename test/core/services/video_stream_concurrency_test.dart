/*
 * File: video_stream_concurrency_test.dart
 * Description: Unit tests for VideoStreamServer verifying concurrency, in-flight Future metadata deduplication, transient failure retries, and reference-counted registration.
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
import 'package:telstorage/features/viewer/presentation/screens/video_player/viewmodel/video_player_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoStreamServer server;
  late Directory tempDir;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('vss_conc_test_');
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

  group('VideoStreamServer Concurrency & Lifecycle Tests', () {
    test('TC-VSS-C01: concurrent requests share a single in-flight metadata download', () async {
      final chunkBytes = Uint8List.fromList(List.generate(64, (i) => i));
      final testRecord = FileRecord(
        fileId: 'stream_vid_conc_1',
        name: 'conc.mp4',
        metadataMessageId: 70,
        metadataFileId: 'meta_conc_id',
        sizeMb: chunkBytes.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_conc',
      );

      final metadataJson = jsonEncode({
        'file_id': testRecord.fileId,
        'name': testRecord.name,
        'size_mb': testRecord.sizeMb,
        'chunk_count': 1,
        'chunks': [
          {
            'index': 1,
            'message_id': 71,
            'file_id': 'tg_chunk_conc_001',
            'size_mb': testRecord.sizeMb,
            'part_name': 'conc.mp4',
          }
        ],
      });

      final fakeTelegram = _SlowFakeTelegramService(delay: const Duration(milliseconds: 60));
      fakeTelegram.files['meta_conc_id'] = Uint8List.fromList(utf8.encode(metadataJson));
      fakeTelegram.files['tg_chunk_conc_001'] = chunkBytes;

      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);

      server.registerFile(testRecord);
      server.setChunkFetcherForTesting(null);

      final port = await server.start();
      expect(port, greaterThan(0));

      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId);

        // Fire 3 requests concurrently before the first metadata download finishes
        final f1 = client.getUrl(Uri.parse(streamUrl)).then((r) => r.close());
        final f2 = client.getUrl(Uri.parse(streamUrl)).then((r) => r.close());
        final f3 = client.getUrl(Uri.parse(streamUrl)).then((r) => r.close());

        final responses = await Future.wait([f1, f2, f3]);
        for (final res in responses) {
          expect(res.statusCode, equals(HttpStatus.ok));
          await res.drain();
        }

        // Despite 3 concurrent requests, metadata was downloaded exactly ONCE!
        expect(fakeTelegram.metadataDownloadCount, equals(1));
      } finally {
        client.close();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });

    test('TC-VSS-C02: failed metadata fetch is evicted from in-flight map allowing retry', () async {
      final chunkBytes = Uint8List.fromList(List.generate(32, (i) => i));
      final testRecord = FileRecord(
        fileId: 'stream_vid_retry_1',
        name: 'retry.mp4',
        metadataMessageId: 80,
        metadataFileId: 'meta_retry_id',
        sizeMb: chunkBytes.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_retry',
      );

      final metadataJson = jsonEncode({
        'file_id': testRecord.fileId,
        'name': testRecord.name,
        'size_mb': testRecord.sizeMb,
        'chunk_count': 1,
        'chunks': [
          {
            'index': 1,
            'message_id': 81,
            'file_id': 'tg_chunk_retry_001',
            'size_mb': testRecord.sizeMb,
            'part_name': 'retry.mp4',
          }
        ],
      });

      final fakeTelegram = _FailingThenSucceedingTelegramService(
        metaId: 'meta_retry_id',
        metaBytes: Uint8List.fromList(utf8.encode(metadataJson)),
        chunkId: 'tg_chunk_retry_001',
        chunkBytes: chunkBytes,
      );

      ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
      ServiceLocator.instance.setInitializedForTesting(true);

      server.registerFile(testRecord);
      server.setChunkFetcherForTesting(null);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId);

        // First request fails because Telegram threw
        final req1 = await client.getUrl(Uri.parse(streamUrl));
        final res1 = await req1.close();
        expect(res1.statusCode, equals(HttpStatus.internalServerError));
        await res1.drain();

        // Second request retries and succeeds because failed future was evicted
        final req2 = await client.getUrl(Uri.parse(streamUrl));
        final res2 = await req2.close();
        expect(res2.statusCode, equals(HttpStatus.ok));
        await res2.drain();
      } finally {
        client.close();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });

    test('TC-VSS-C03: reference-counted registration prevents premature unregistration across consumers', () async {
      final sampleVideoData = Uint8List.fromList(List.generate(40, (i) => i));
      final testRecord = FileRecord(
        fileId: 'stream_vid_refcount_1',
        name: 'refcount.mp4',
        metadataMessageId: 90,
        sizeMb: sampleVideoData.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_refcount',
      );

      server.setChunkFetcherForTesting((fileId, chunkIndex, chunkCount) async => sampleVideoData);

      // Two players register the same file
      server.registerFile(testRecord);
      server.registerFile(testRecord);

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(testRecord.fileId);

        // Player 1 unregisters
        server.unregisterFile(testRecord.fileId);

        // File must STILL be available for Player 2!
        final req1 = await client.getUrl(Uri.parse(streamUrl));
        final res1 = await req1.close();
        expect(res1.statusCode, equals(HttpStatus.ok));
        await res1.drain();

        // Player 2 unregisters
        server.unregisterFile(testRecord.fileId);

        // Now both have unregistered -> 404
        final req2 = await client.getUrl(Uri.parse(streamUrl));
        final res2 = await req2.close();
        expect(res2.statusCode, equals(HttpStatus.notFound));
        await res2.drain();
      } finally {
        client.close();
      }
    });

    test('TC-VSS-C04: VideoPlayerViewModel cleans up registration on initialization failure', () async {
      final failingRecord = FileRecord(
        fileId: 'stream_vid_fail_vm_1',
        name: 'fail.mp4',
        metadataMessageId: 95,
        sizeMb: 0.1,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_fail',
      );

      final viewModel = VideoPlayerViewModel();
      // initialize will fail because VideoPlayerController cannot connect / is in headless test
      await viewModel.initialize(failingRecord);

      expect(viewModel.isInitialized, isFalse);
      expect(viewModel.errorMessage, isNotNull);
      expect(viewModel.currentFile, isNull);

      // Verify file is NOT leaked in VideoStreamServer's active files
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(failingRecord.fileId);
        final req = await client.getUrl(Uri.parse(streamUrl));
        final res = await req.close();
        expect(res.statusCode, equals(HttpStatus.notFound));
        await res.drain();
      } finally {
        client.close();
        viewModel.dispose();
      }
    });

    test('TC-VSS-C05: overlapping initialize() calls safely handle race condition', () async {
      final record1 = FileRecord(
        fileId: 'stream_vid_race_1',
        name: 'race1.mp4',
        metadataMessageId: 96,
        sizeMb: 0.1,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_race_1',
      );

      final record2 = FileRecord(
        fileId: 'stream_vid_race_2',
        name: 'race2.mp4',
        metadataMessageId: 97,
        sizeMb: 0.1,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'dummy_race_2',
      );

      final viewModel = VideoPlayerViewModel();
      try {
        final f1 = viewModel.initialize(record1);
        final f2 = viewModel.initialize(record2);
        await Future.wait([f1, f2]);

        // Stale record1 must not overwrite record2
        expect(viewModel.currentFile?.fileId, isNot(equals(record1.fileId)));
      } finally {
        viewModel.dispose();
      }
    });
  });
}

class _SlowFakeTelegramService extends TelegramService {
  final Duration delay;
  final Map<String, Uint8List> files = {};
  int metadataDownloadCount = 0;

  _SlowFakeTelegramService({required this.delay});

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
  ]) async {
    await Future.delayed(delay);
    if (fileId.startsWith('meta_')) {
      metadataDownloadCount++;
    }
    final data = files[fileId];
    if (data != null) return data;
    throw Exception('File not found: $fileId');
  }
}

class _FailingThenSucceedingTelegramService extends TelegramService {
  final String metaId;
  final Uint8List metaBytes;
  final String chunkId;
  final Uint8List chunkBytes;
  bool _hasFailedOnce = false;

  _FailingThenSucceedingTelegramService({
    required this.metaId,
    required this.metaBytes,
    required this.chunkId,
    required this.chunkBytes,
  });

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
  ]) async {
    if (fileId == metaId) {
      if (!_hasFailedOnce) {
        _hasFailedOnce = true;
        throw Exception('Simulated Telegram transient network error');
      }
      return metaBytes;
    }
    if (fileId == chunkId) {
      return chunkBytes;
    }
    throw Exception('File not found: $fileId');
  }
}
