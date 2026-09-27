/*
 * File: video_stream_seek_bandwidth_optimization_repro_test.dart
 * Description: Automated reproduction test verifying that seeking terminates ghost stream loops and prefetch does not duplicate in-flight chunks.
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/chunk_info.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/in_flight_chunk_registry.dart';
import 'package:telstorage/core/services/video_chunk_cache_manager.dart';
import 'package:telstorage/core/services/video_stream_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late VideoStreamServer server;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('bandwidth_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
    VideoChunkCacheManager.instance.setBaseDirForTesting(tempDir);
    server = VideoStreamServer.instance;
  });

  tearDown(() async {
    await server.stop();
    VideoChunkCacheManager.instance.setBaseDirForTesting(null);
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('TC-SEEK-GHOST-LOOP-ABORT-REPRO: When user seeks, previous stream loop is aborted and does not download old chunks', () async {
    const partSize = 1024 * 1024; // 1 MB per chunk
    server.setPartSizeForTesting(partSize);

    final testRecord = FileRecord(
      fileId: 'vid_seek_test',
      name: 'video.mp4',
      metadataMessageId: 100,
      sizeMb: 5.0, // 5 MB = 5 chunks (0, 1, 2, 3, 4)
      mimeType: 'video/mp4',
      uploadedAt: DateTime(2026, 9, 27),
      chunkCount: 5,
      sha256Hash: 'dummy',
    );

    server.setFileRecordProviderForTesting((fileId) async => testRecord);

    final chunkMap = {
      1: ChunkInfo(index: 1, messageId: 1, fileId: 'chunk_0', sizeMb: 1.0),
      2: ChunkInfo(index: 2, messageId: 2, fileId: 'chunk_1', sizeMb: 1.0),
      3: ChunkInfo(index: 3, messageId: 3, fileId: 'chunk_2', sizeMb: 1.0),
      4: ChunkInfo(index: 4, messageId: 4, fileId: 'chunk_3', sizeMb: 1.0),
      5: ChunkInfo(index: 5, messageId: 5, fileId: 'chunk_4', sizeMb: 1.0),
    };
    server.seedMetadata(testRecord.fileId, chunkMap);

    final streamedChunks = <int>[];
    final chunk0Controller = StreamController<List<int>>();

    server.pipeliner.setStreamFetcherForTesting((fileId, chunkIdx) {
      streamedChunks.add(chunkIdx);
      if (chunkIdx == 0) {
        return chunk0Controller.stream;
      }
      return Stream.value(Uint8List(partSize));
    });

    await server.start();
    final reg = server.registerFile(testRecord);

    final client = HttpClient();
    final req1 = await client.getUrl(Uri.parse(server.getStreamUrl(testRecord.fileId)));
    req1.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    unawaited(req1.close());

    // Wait briefly for request 1 to start chunk 0
    await Future.delayed(const Duration(milliseconds: 50));
    expect(streamedChunks, contains(0));

    // Now simulate user seek to chunk 3 (byte offset 3 * partSize)
    final req2 = await client.getUrl(Uri.parse(server.getStreamUrl(testRecord.fileId)));
    req2.headers.set(HttpHeaders.rangeHeader, 'bytes=${3 * partSize}-');
    unawaited(req2.close());

    await Future.delayed(const Duration(milliseconds: 50));

    // Finish chunk 0 for request 1
    chunk0Controller.add(Uint8List(partSize));
    await chunk0Controller.close();

    // Allow async processing
    await Future.delayed(const Duration(milliseconds: 150));

    // Request 1 must NOT continue sequentially into chunk 1 and chunk 2 after request 2 arrived!
    expect(streamedChunks.contains(1), isFalse,
        reason: 'Request 1 should abort and NOT stream chunk 1 after seek to chunk 3');
    expect(streamedChunks.contains(2), isFalse,
        reason: 'Request 1 should abort and NOT stream chunk 2 after seek to chunk 3');

    reg.dispose();
  });

  test('TC-PREFETCH-IN-FLIGHT-DEDUP-REPRO: Prefetch loop must not start download if chunk is already in-flight', () async {
    const partSize = 1024 * 1024;
    server.setPartSizeForTesting(partSize);

    final testRecord = FileRecord(
      fileId: 'vid_dedup_test',
      name: 'video.mp4',
      metadataMessageId: 200,
      sizeMb: 5.0,
      mimeType: 'video/mp4',
      uploadedAt: DateTime(2026, 9, 27),
      chunkCount: 5,
      sha256Hash: 'dummy',
    );

    // Seed chunk 0 on disk so prefetch worker can evaluate next chunk (chunk 1)
    await VideoChunkCacheManager.instance.saveChunk(testRecord.fileId, 0, Uint8List(partSize));

    final prefetchDownloaderCalls = <int>[];
    server.prefetchCoordinator.setDownloaderForTesting((record, chunkIdx, priority) async {
      prefetchDownloaderCalls.add(chunkIdx);
      return Uint8List(partSize);
    });

    // Simulate chunk 1 already being in-flight in registry (streamed by pipeliner)
    final inFlight = InFlightChunkRegistry.instance.register(testRecord.fileId, 1);

    // Trigger prefetch coordinator for chunk 0
    server.prefetchCoordinator.onChunkRequested(testRecord, 0);

    // Allow worker loop to run
    await Future.delayed(const Duration(milliseconds: 150));

    // The prefetch downloader must NOT have called download for chunk 1 since it was already in-flight!
    expect(prefetchDownloaderCalls.contains(1), isFalse,
        reason: 'Prefetch coordinator must not start duplicate download for chunk 1 while it is in-flight');

    inFlight.complete(File('${tempDir.path}/dummy_1'));
  });
}
