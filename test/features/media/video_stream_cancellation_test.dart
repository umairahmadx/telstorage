/*
 * File: video_stream_cancellation_test.dart
 * Description: Automated reproduction tests for video streaming cancellation, exit cleanup, and instant startup without blocking 19 MB chunk preflights.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/chunk_info.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/video_chunk_cache_manager.dart';
import 'package:telstorage/core/services/video_prefetch_coordinator.dart';
import 'package:telstorage/core/services/video_stream_pipeliner.dart';
import 'package:telstorage/core/services/video_stream_server.dart';

class TrackingTelegramService extends TelegramService {
  int downloadByFileIdCallCount = 0;
  final List<String> downloadedFileIds = [];
  final Map<String, Uint8List> fileData = {};
  CancelToken? lastCancelToken;
  final Completer<void> downloadStartedCompleter = Completer<void>();
  bool downloadWasCancelled = false;

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
    CancelToken? cancelToken,
  ]) async {
    downloadByFileIdCallCount++;
    downloadedFileIds.add(fileId);
    if (fileData.containsKey(fileId)) {
      return fileData[fileId]!;
    }
    return Uint8List(100);
  }

  @override
  Future<Uint8List> downloadByFileIdWithProgress(
    String fileId, {
    RequestPriority priority = RequestPriority.normal,
    void Function(int count, int total)? onReceiveProgress,
    CancelToken? cancelToken,
  }) async {
    downloadByFileIdCallCount++;
    downloadedFileIds.add(fileId);
    lastCancelToken = cancelToken;

    if (!downloadStartedCompleter.isCompleted) {
      downloadStartedCompleter.complete();
    }

    if (cancelToken != null) {
      final cancelCompleter = Completer<Uint8List>();
      cancelToken.whenCancel.then((_) {
        downloadWasCancelled = true;
        if (!cancelCompleter.isCompleted) {
          cancelCompleter.completeError(
            DioException(
              requestOptions: RequestOptions(path: fileId),
              type: DioExceptionType.cancel,
              message: 'Request cancelled',
            ),
          );
        }
      });

      // Simulate long download that waits for cancellation
      return await cancelCompleter.future;
    }

    // If no cancel token, simulate long download
    await Future.delayed(const Duration(seconds: 10));
    return Uint8List(100);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late VideoStreamServer server;
  late VideoChunkCacheManager cacheManager;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('vss_cancel_test_');
    cacheManager = VideoChunkCacheManager.instance;
    cacheManager.setBaseDirForTesting(tempDir);
    server = VideoStreamServer.instance;
  });

  tearDown(() async {
    await server.stop();
    server.setFileRecordProviderForTesting(null);
    server.setChunkFetcherForTesting(null);
    cacheManager.setBaseDirForTesting(null);
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  group('Video Stream Cancellation & Instant Startup Reproduction Tests', () {
    test('TC-REPRO-01: Startup does NOT synchronously call downloadByFileId for chunk 0 when not cached', () async {
      const filename = 'startup_test.mp4';
      const fakeSizeMb = 38.0;

      final record = FileRecord(
        fileId: 'startup_vid_repro_1',
        name: filename,
        metadataMessageId: 10,
        metadataFileId: 'meta_startup_id',
        sizeMb: fakeSizeMb,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: 'dummy_hash',
      );

      final metadataJson = jsonEncode({
        'file_id': record.fileId,
        'name': record.name,
        'size_mb': record.sizeMb,
        'chunk_count': 2,
        'chunks': [
          {'index': 1, 'message_id': 11, 'file_id': 'tg_c1', 'size_mb': 19.0},
          {'index': 2, 'message_id': 12, 'file_id': 'tg_c2', 'size_mb': 19.0},
        ],
      });

      final trackingTg = TrackingTelegramService();
      ServiceLocator.instance.setTelegramForTesting(trackingTg);
      ServiceLocator.instance.setInitializedForTesting(true);

      server.registerFile(record);
      server.setChunkFetcherForTesting((fileId, chunkIdx, chunkCount) async {
        // Return small packet immediately
        return Uint8List(1024);
      });

      // Inject metadata directly so metadata fetch doesn't pollute call counts
      final metaBytes = Uint8List.fromList(utf8.encode(metadataJson));
      trackingTg.fileData[record.metadataFileId!] = metaBytes;

      await server.start();
      final client = HttpClient();
      try {
        final streamUrl = server.getStreamUrl(record.fileId, record.name);
        final req = await client.getUrl(Uri.parse(streamUrl));
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-100');
        final res = await req.close();

        expect(res.statusCode, equals(HttpStatus.partialContent));
        await res.drain();

        // BUG REPRODUCTION CHECK:
        // Before fix: lines 287-290 called downloadByFileId('tg_c1') which downloaded the full 19 MB.
        // downloadByFileIdCallCount should be 0 because streaming should NOT download full chunks synchronously!
        expect(
          trackingTg.downloadedFileIds.contains('tg_c1'),
          isFalse,
          reason: 'Chunk 0 should never be synchronously downloaded via downloadByFileId before serving stream!',
        );
      } finally {
        client.close();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });

    test('TC-REPRO-02: Unregistering file cancels in-flight pipeliner stream and cleans up without caching', () async {
      final pipeliner = VideoStreamPipeliner();
      final streamController = StreamController<List<int>>();

      pipeliner.setStreamFetcherForTesting((fileId, chunkIdx) {
        return streamController.stream;
      });

      final record = FileRecord(
        fileId: 'repro_cancel_vid',
        name: 'test_cancel.mp4',
        metadataMessageId: 20,
        sizeMb: 50.0,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026),
        chunkCount: 3,
        sha256Hash: 'dummy',
        metadataFileId: 'meta_dummy',
      );

      final outputSink = StreamController<List<int>>();
      outputSink.stream.listen((_) {});

      // Start streaming chunk 0
      final pipeFuture = pipeliner.pipeChunkRange(
        record: record,
        chunkIndex: 0,
        sliceStart: 0,
        sliceEnd: 100000,
        output: outputSink.sink,
      );

      // Emit first packet
      streamController.add(List.generate(1024, (i) => i % 256));
      await Future.delayed(const Duration(milliseconds: 20));

      // User backs out -> unregister file / cancel for file
      pipeliner.cancelForFile(record.fileId);

      // Wait for pipeliner to finish
      try {
        await pipeFuture.timeout(const Duration(seconds: 2));
      } catch (_) {}

      await outputSink.close();
      await streamController.close();

      // Verify chunk was NOT committed to cache
      final cached = await cacheManager.getCachedChunk(record.fileId, 0);
      expect(cached, isNull, reason: 'Cancelled pipeliner stream must not commit chunk to cache');

      // Verify no temporary .part.tmp files remain
      final chunkDir = await cacheManager.getChunkDir(record.fileId);
      final tmpFiles = chunkDir
          .listSync()
          .where((f) => f.path.contains('.tmp'))
          .toList();
      expect(tmpFiles, isEmpty, reason: 'Temporary part files must be deleted on cancel');
    });

    test('TC-REPRO-03: VideoPrefetchCoordinator aborts in-flight download on cancelForFile via CancelToken', () async {
      final coordinator = VideoPrefetchCoordinator(prefetchWindowSize: 2);
      final trackingTg = TrackingTelegramService();
      ServiceLocator.instance.setTelegramForTesting(trackingTg);
      ServiceLocator.instance.setInitializedForTesting(true);

      final record = FileRecord(
        fileId: 'repro_prefetch_cancel_vid',
        name: 'prefetch_test.mp4',
        metadataMessageId: 30,
        metadataFileId: 'meta_pfc',
        sizeMb: 60.0,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026),
        chunkCount: 3,
        sha256Hash: 'dummy',
      );

      final chunkMap = <int, ChunkInfo>{
        1: ChunkInfo(index: 1, messageId: 31, fileId: 'tg_pfc_1', sizeMb: 19.0),
        2: ChunkInfo(index: 2, messageId: 32, fileId: 'tg_pfc_2', sizeMb: 19.0),
        3: ChunkInfo(index: 3, messageId: 33, fileId: 'tg_pfc_3', sizeMb: 19.0),
      };

      try {
        // Trigger prefetch on chunk 0 (which starts downloading chunk 1)
        coordinator.onChunkRequested(record, 0, chunkMap: chunkMap);

        // Wait for download to start
        await trackingTg.downloadStartedCompleter.future.timeout(const Duration(seconds: 2));

        // User backs out
        await coordinator.cancelForFile(record.fileId);

        // BUG REPRODUCTION CHECK:
        // Before fix: downloadWasCancelled is false because no CancelToken was passed or cancelled!
        expect(
          trackingTg.downloadWasCancelled,
          isTrue,
          reason: 'In-flight prefetch download must be cancelled via CancelToken on cancelForFile',
        );
      } finally {
        await coordinator.cancelAll();
        ServiceLocator.instance.setInitializedForTesting(false);
      }
    });
  });
}
