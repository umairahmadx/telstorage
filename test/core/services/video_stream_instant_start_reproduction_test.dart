/*
 * File: video_stream_instant_start_reproduction_test.dart
 * Description: Reproduction test verifying that initial video playback stream is blocked by prewarmHeaders awaiting a full chunk download instead of streaming packets instantly.
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
    tempDir = await Directory.systemTemp.createTemp('instant_start_test_');
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

  test('REPRODUCTION (RED): Video playback start (bytes=0-) must stream initial packets immediately and NOT block on full chunk prewarm', () async {
    const partSize = 20 * 1024 * 1024; // 20 MB
    server.setPartSizeForTesting(partSize);

    final chunk0Bytes = Uint8List(partSize);
    chunk0Bytes[0] = 0xAA;
    chunk0Bytes[1] = 0xBB;

    final testRecord = FileRecord(
      fileId: 'repro_vid_123',
      name: 'VID20260502165953.mp4',
      metadataMessageId: 100,
      sizeMb: 40.0,
      mimeType: 'video/mp4',
      uploadedAt: DateTime(2026, 5, 2),
      chunkCount: 2, // Chunks 0 and 1
      sha256Hash: 'dummy',
    );

    server.setFileRecordProviderForTesting((fileId) async => testRecord);

    final chunkMap = {
      1: ChunkInfo(index: 1, messageId: 6029, fileId: 'target_chunk_0', sizeMb: 20.0, partName: 'part1'),
      2: ChunkInfo(index: 2, messageId: 6031, fileId: 'target_chunk_1', sizeMb: 20.0, partName: 'part2'),
    };
    server.seedMetadata(testRecord.fileId, chunkMap);

    // Simulate prewarm downloader hanging / downloading 20MB over slow network
    final prewarmChunk0Completer = Completer<Uint8List>();
    final prewarmChunk1Completer = Completer<Uint8List>();
    final prewarmedTargets = <int>[];

    server.prefetchCoordinator.setDownloaderForTesting((record, chunkIdx, priority) {
      prewarmedTargets.add(chunkIdx);
      // Mirror production line 384: prewarm registers in InFlightChunkRegistry
      InFlightChunkRegistry.instance.register(record.fileId, chunkIdx);
      if (chunkIdx == 0) return prewarmChunk0Completer.future;
      return prewarmChunk1Completer.future;
    });

    // Simulate real-time streaming pipeline that yields 64KB packet immediately
    final streamController = StreamController<List<int>>();
    server.pipeliner.setStreamFetcherForTesting((fileId, chunkIdx) {
      return streamController.stream;
    });

    await server.start();
    final reg = server.registerFile(testRecord);

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(server.getStreamUrl(testRecord.fileId)));
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');

      // The pipeliner should start streaming immediately and emit packet
      final responseFuture = request.close();

      // Emit first 64KB packet to the network stream
      final firstPacket = Uint8List(65536);
      firstPacket[0] = 0xDE;
      firstPacket[1] = 0xAD;
      streamController.add(firstPacket);

      // We expect the HTTP response to deliver the first packet in < 500ms
      // WITHOUT waiting for prewarmChunk0Completer (which simulates the 15-second 20MB download)
      final response = await responseFuture.timeout(const Duration(milliseconds: 500));
      final receivedFirstChunk = await response.first.timeout(const Duration(milliseconds: 500));

      expect(receivedFirstChunk, isNotEmpty);
      expect(receivedFirstChunk[0], equals(0xDE));
    } finally {
      reg.dispose();
      client.close();
      await streamController.close();
    }
  });
}
