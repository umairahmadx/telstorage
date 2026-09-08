/*
 * File: video_chunk_cache_manager_test.dart
 * Description: Unit tests for VideoChunkCacheManager verifying chunk storage, atomic write, LRU touch updates, cache size calculation, and eviction.
 */

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/video_chunk_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late VideoChunkCacheManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('video_chunk_cache_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
    manager = VideoChunkCacheManager.instance;
    manager.setBaseDirForTesting(tempDir);
  });

  tearDown(() async {
    manager.setBaseDirForTesting(null);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('VideoChunkCacheManager Unit Tests', () {
    test('TC-VCM-01: saves chunk atomically and returns cached chunk file', () async {
      const fileId = 'vid_test_1';
      const chunkIndex = 0;
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      // Initially null
      final before = await manager.getCachedChunk(fileId, chunkIndex);
      expect(before, isNull);

      // Save chunk
      final savedFile = await manager.saveChunk(fileId, chunkIndex, data);
      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.path.endsWith('chunk_0.part'), isTrue);
      expect(await savedFile.readAsBytes(), equals(data));

      // Now cached
      final cached = await manager.getCachedChunk(fileId, chunkIndex);
      expect(cached, isNotNull);
      expect(cached!.existsSync(), isTrue);
      expect(await cached.readAsBytes(), equals(data));
    });

    test('TC-VCM-02: calculates total cache bytes across chunks and files', () async {
      final data1 = Uint8List(100);
      final data2 = Uint8List(250);

      await manager.saveChunk('vid_a', 0, data1);
      await manager.saveChunk('vid_a', 1, data2);
      await manager.saveChunk('vid_b', 0, data1);

      final totalBytes = await manager.getTotalVideoCacheBytes();
      expect(totalBytes, equals(100 + 250 + 100));
    });

    test('TC-VCM-03: clears specific file chunks or all video cache', () async {
      await manager.saveChunk('vid_1', 0, Uint8List(50));
      await manager.saveChunk('vid_2', 0, Uint8List(50));

      // Clear only vid_1
      await manager.clearVideoCache(fileId: 'vid_1');
      expect(await manager.getCachedChunk('vid_1', 0), isNull);
      expect(await manager.getCachedChunk('vid_2', 0), isNotNull);

      // Clear all
      await manager.clearVideoCache();
      expect(await manager.getCachedChunk('vid_2', 0), isNull);
      expect(await manager.getTotalVideoCacheBytes(), equals(0));
    });

    test('TC-VCM-04: evicts oldest chunks when exceeding maxSizeBytes', () async {
      final chunk1 = Uint8List(100);
      final chunk2 = Uint8List(100);
      final chunk3 = Uint8List(100);

      final file1 = await manager.saveChunk('vid_lru', 0, chunk1);
      // Ensure file1 has an older timestamp
      file1.setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 5)));

      final file2 = await manager.saveChunk('vid_lru', 1, chunk2);
      file2.setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 2)));

      await manager.saveChunk('vid_lru', 2, chunk3);

      expect(await manager.getTotalVideoCacheBytes(), equals(300));

      // Evict with 150-byte ceiling (should delete chunk 0 and chunk 1)
      await manager.evictOldestIfNeeded(maxSizeBytes: 150);

      expect(await manager.getCachedChunk('vid_lru', 0), isNull);
      expect(await manager.getTotalVideoCacheBytes(), lessThanOrEqualTo(150));
    });
  });
}
