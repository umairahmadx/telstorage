/*
 * File: video_stream_probe_immunity_test.dart
 * Description: Reproduction and regression tests verifying demuxer header probe immunity and in-flight chunk de-duplication.
 */

import 'dart:async';
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
    tempDir = await Directory.systemTemp.createTemp('probe_immunity_test_');
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

  test('TC-VS-P01: Container header probe (0 -> lastChunk -> 0) does NOT thrash prefetch queue', () async {
    final coordinator = VideoPrefetchCoordinator();
    final downloadInvocations = <int>[];
    final downloadCompleters = <int, Completer<Uint8List>>{
      1: Completer<Uint8List>(),
    };

    coordinator.setDownloaderForTesting((record, chunkIdx, priority) async {
      downloadInvocations.add(chunkIdx);
      final completer = downloadCompleters[chunkIdx] ?? Completer<Uint8List>();
      return completer.future;
    });

    final record = FileRecord(
      fileId: 'probe_test_vid',
      name: 'probe_test.mp4',
      metadataMessageId: 0,
      sizeMb: 40.0,
      mimeType: 'video/mp4',
      uploadedAt: DateTime.now(),
      chunkCount: 2, // Chunks 0 and 1
      sha256Hash: 'dummy',
    );

    // 1. Initial start at chunk 0
    coordinator.onChunkRequested(record, 0);
    await Future.delayed(const Duration(milliseconds: 10));

    // 2. Demuxer probe to lastChunk (chunk 1 for moov atom)
    coordinator.onChunkRequested(record, 1);
    await Future.delayed(const Duration(milliseconds: 10));

    // 3. Demuxer returns to start (chunk 0) to decode frames
    coordinator.onChunkRequested(record, 0);
    await Future.delayed(const Duration(milliseconds: 10));

    // Verify that demuxer probe (1 -> 0) did not trigger multiple redundant invocations
    final chunk1Invocations = downloadInvocations.where((c) => c == 1).length;
    expect(
      chunk1Invocations,
      lessThanOrEqualTo(1),
      reason: 'Demuxer probe (1 -> 0) must retain session without redundant duplicate downloads.',
    );
  });

  test('TC-VS-P02: Genuine user seek cancels old lookahead worker and re-anchors to new target', () async {
    final coordinator = VideoPrefetchCoordinator();
    final downloadInvocations = <int>[];
    final downloadCompleters = <int, Completer<Uint8List>>{
      1: Completer<Uint8List>(),
      4: Completer<Uint8List>(),
    };

    coordinator.setDownloaderForTesting((record, chunkIdx, priority) async {
      downloadInvocations.add(chunkIdx);
      final completer = downloadCompleters[chunkIdx] ?? Completer<Uint8List>();
      return completer.future;
    });

    final record = FileRecord(
      fileId: 'multi_chunk_vid',
      name: 'large_movie.mp4',
      metadataMessageId: 0,
      sizeMb: 120.0,
      mimeType: 'video/mp4',
      uploadedAt: DateTime.now(),
      chunkCount: 6, // Chunks 0..5
      sha256Hash: 'dummy',
    );

    // 1. Start playback at chunk 0
    coordinator.onChunkRequested(record, 0);
    await Future.delayed(const Duration(milliseconds: 10));

    // 2. User seeks to chunk 3
    coordinator.onChunkRequested(record, 3);
    await Future.delayed(const Duration(milliseconds: 10));

    // Worker should have re-anchored to seek target (prefethcing chunk 4)
    expect(downloadInvocations.contains(4), isTrue);
  });
}

