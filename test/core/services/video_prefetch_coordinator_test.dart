/*
 * File: video_prefetch_coordinator_test.dart
 * Description: Unit tests for VideoPrefetchCoordinator verifying sliding-window lookahead, seek cancellation, cache-awareness, and EOF boundary handling.
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/chunk_info.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/video_chunk_cache_manager.dart';
import 'package:telstorage/core/services/video_prefetch_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late VideoChunkCacheManager cacheManager;
  late VideoPrefetchCoordinator coordinator;

  FileRecord createTestRecord({
    String fileId = 'prefetch_test_file',
    int chunkCount = 10,
    double sizeMb = 190.0,
  }) {
    return FileRecord(
      fileId: fileId,
      name: 'test_video.mp4',
      sizeMb: sizeMb,
      uploadedAt: DateTime.now(),
      mimeType: 'video/mp4',
      chunkCount: chunkCount,
      metadataMessageId: 1,
      sha256Hash: 'dummy_hash',
      metadataFileId: 'meta_$fileId',
    );
  }

  Map<int, ChunkInfo> createChunkMap(int count) {
    final map = <int, ChunkInfo>{};
    for (int i = 1; i <= count; i++) {
      map[i] = ChunkInfo(
        index: i,
        messageId: i,
        fileId: 'tg_chunk_file_$i',
        sizeMb: 19.0,
      );
    }
    return map;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('video_prefetch_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
    cacheManager = VideoChunkCacheManager.instance;
    cacheManager.setBaseDirForTesting(tempDir);
    coordinator = VideoPrefetchCoordinator(prefetchWindowSize: 2);
  });

  tearDown(() async {
    await coordinator.cancelAll();
    cacheManager.setBaseDirForTesting(null);
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('VideoPrefetchCoordinator Unit Tests', () {
    test('TC-VPC-01: Sequential sliding window pre-buffers chunks N+1 and N+2 in background', () async {
      final record = createTestRecord();
      final chunkMap = createChunkMap(10);
      final downloadedChunks = <int>[];
      final priorities = <RequestPriority>[];

      coordinator.setDownloaderForTesting((rec, chunkIdx, priority) async {
        downloadedChunks.add(chunkIdx);
        priorities.add(priority);
        return Uint8List.fromList([1, 2, 3, chunkIdx]);
      });

      // User starts watching chunk 0
      coordinator.onChunkRequested(record, 0, chunkMap: chunkMap);

      await coordinator.waitForWorkerForTesting(record.fileId)?.timeout(const Duration(seconds: 3));

      // Should prefetch chunks 1 and 2
      expect(downloadedChunks, equals([1, 2]));
      expect(priorities, equals([RequestPriority.background, RequestPriority.background]));

      // Verify chunks were saved into cache
      final cached1 = await cacheManager.getCachedChunk(record.fileId, 1);
      final cached2 = await cacheManager.getCachedChunk(record.fileId, 2);
      expect(cached1, isNotNull);
      expect(cached2, isNotNull);
    });

    test('TC-VPC-02: Cache hit avoidance skips chunks already in disk cache', () async {
      final record = createTestRecord();
      final chunkMap = createChunkMap(10);

      // Pre-populate chunk 1 in cache
      await cacheManager.saveChunk(record.fileId, 1, Uint8List.fromList([42]));

      final downloadedChunks = <int>[];

      coordinator.setDownloaderForTesting((rec, chunkIdx, priority) async {
        downloadedChunks.add(chunkIdx);
        return Uint8List.fromList([99]);
      });

      // User starts chunk 0. Window is [1, 2], chunk 1 is cached -> should only download chunk 2
      coordinator.onChunkRequested(record, 0, chunkMap: chunkMap);

      await coordinator.waitForWorkerForTesting(record.fileId)?.timeout(const Duration(seconds: 3));
      expect(downloadedChunks, equals([2]));
    });

    test('TC-VPC-03: Seek cancels old prefetch queue and re-anchors to new target', () async {
      final record = createTestRecord();
      final chunkMap = createChunkMap(10);
      final downloadedChunks = <int>[];
      final chunk1Started = Completer<void>();
      final chunk1CanProceed = Completer<void>();

      coordinator.setDownloaderForTesting((rec, chunkIdx, priority) async {
        downloadedChunks.add(chunkIdx);
        if (chunkIdx == 1) {
          chunk1Started.complete();
          // Simulate slow download
          await chunk1CanProceed.future;
        }
        return Uint8List.fromList([chunkIdx]);
      });

      // User requests chunk 0 -> chunk 1 begins downloading
      coordinator.onChunkRequested(record, 0, chunkMap: chunkMap);
      await chunk1Started.future;

      // User immediately seeks to chunk 7!
      coordinator.onChunkRequested(record, 7, chunkMap: chunkMap);

      // Release chunk 1
      chunk1CanProceed.complete();

      // Wait for new worker (session re-anchored on chunk 7) to complete
      await coordinator.waitForWorkerForTesting(record.fileId)?.timeout(const Duration(seconds: 3));

      // Chunks 8 and 9 must be pre-buffered
      expect(downloadedChunks, contains(8));
      expect(downloadedChunks, contains(9));
      // Chunk 2 must never have been downloaded
      expect(downloadedChunks, isNot(contains(2)));
    });

    test('TC-VPC-04: End-of-file boundary clamps lookahead to chunkCount - 1', () async {
      final record = createTestRecord(chunkCount: 3); // Chunks 0, 1, 2
      final chunkMap = createChunkMap(3);
      final downloadedChunks = <int>[];

      coordinator.setDownloaderForTesting((rec, chunkIdx, priority) async {
        downloadedChunks.add(chunkIdx);
        return Uint8List.fromList([chunkIdx]);
      });

      // Playing chunk 1 of 3 (indices 0, 1, 2). Only chunk 2 exists ahead.
      coordinator.onChunkRequested(record, 1, chunkMap: chunkMap);

      await coordinator.waitForWorkerForTesting(record.fileId)?.timeout(const Duration(seconds: 3));

      expect(downloadedChunks, equals([2]));

      // Playing chunk 2 (last chunk) -> nothing ahead
      downloadedChunks.clear();
      coordinator.onChunkRequested(record, 2, chunkMap: chunkMap);
      await coordinator.waitForWorkerForTesting(record.fileId)?.timeout(const Duration(seconds: 3));
      expect(downloadedChunks, isEmpty);
    });

    test('TC-VPC-05: cancelForFile aborts active prefetch workers', () async {
      final record = createTestRecord();
      final chunkMap = createChunkMap(10);
      final downloadedChunks = <int>[];
      final slowCompleter = Completer<void>();

      coordinator.setDownloaderForTesting((rec, chunkIdx, priority) async {
        downloadedChunks.add(chunkIdx);
        await slowCompleter.future;
        return Uint8List.fromList([chunkIdx]);
      });

      coordinator.onChunkRequested(record, 0, chunkMap: chunkMap);
      await Future.delayed(const Duration(milliseconds: 50));

      // Release downloader so worker can exit
      slowCompleter.complete();

      // Cancel playback of this file
      await coordinator.cancelForFile(record.fileId);

      // Chunk 2 should not be downloaded
      expect(downloadedChunks.contains(2), isFalse);
    });

    test('TC-VPC-06: in-flight chunk progress tracking updates bytes, fractions, and notifies listeners', () {
      const fileId = 'in_flight_test_vid';
      var notificationCount = 0;
      coordinator.prefetchProgressNotifier.addListener(() {
        notificationCount++;
      });

      // Initially 0
      expect(coordinator.getInFlightBytes(fileId), equals(0));
      expect(coordinator.getInFlightFractions(fileId), isEmpty);

      // Set 10 MB of 20 MB for chunk 1
      coordinator.setMockInFlightProgressForTesting(fileId, 1, 10 * 1024 * 1024, 20 * 1024 * 1024);

      expect(notificationCount, equals(1));
      expect(coordinator.getInFlightBytes(fileId), equals(10 * 1024 * 1024));
      final fractions = coordinator.getInFlightFractions(fileId);
      expect(fractions[1], closeTo(0.5, 0.001));

      // Cancel clears in-flight state
      coordinator.cancelForFile(fileId);
      expect(coordinator.getInFlightBytes(fileId), equals(0));
      expect(coordinator.getInFlightFractions(fileId), isEmpty);
      expect(notificationCount, equals(2));
    });
  });
}
