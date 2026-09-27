import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/video_chunk_cache_manager.dart';
import 'package:telstorage/core/services/video_prefetch_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dual_prewarm_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
    VideoChunkCacheManager.instance.setBaseDirForTesting(tempDir);
  });

  tearDown(() async {
    VideoChunkCacheManager.instance.setBaseDirForTesting(null);
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('prefetch coordinator follows sequential discipline and does not prewarm blindly', () async {
    final coordinator = VideoPrefetchCoordinator();
    final requestedChunks = <int>[];

    coordinator.setDownloaderForTesting((record, chunkIdx, priority) async {
      requestedChunks.add(chunkIdx);
      return Uint8List(100);
    });

    final record = FileRecord(
      fileId: 'multi_chunk_vid',
      name: 'movie.mkv',
      metadataMessageId: 0,
      sizeMb: 100.0,
      mimeType: 'video/x-matroska',
      uploadedAt: DateTime.now(),
      chunkCount: 5, // Chunks 0, 1, 2, 3, 4
      sha256Hash: 'dummy',
    );

    // Initial chunk request for chunk 0
    coordinator.onChunkRequested(record, 0);
    await coordinator.waitForWorkerForTesting(record.fileId);

    // Should prefetch sequentially (lookahead) without blind prewarming
    expect(requestedChunks, contains(1));
    expect(requestedChunks, isNot(contains(4))); // Does NOT prewarm tail chunk
  });
}
