/*
 * File: video_stream_pipeliner_test.dart
 * Description: Unit tests for VideoStreamPipeliner verifying packet-level streaming, real-time slice forwarding, and concurrent disk caching.
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/chunk_info.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/video_chunk_cache_manager.dart';
import 'package:telstorage/core/services/video_stream_pipeliner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late VideoStreamPipeliner pipeliner;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pipeliner_test_');
    VideoChunkCacheManager.instance.setBaseDirForTesting(tempDir);
    pipeliner = VideoStreamPipeliner();
  });

  tearDown(() async {
    VideoChunkCacheManager.instance.setBaseDirForTesting(null);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  final testRecord = FileRecord(
    fileId: 'vid_pipe_test',
    name: 'sample_video.mp4',
    metadataMessageId: 1,
    sizeMb: 50.0,
    mimeType: 'video/mp4',
    uploadedAt: DateTime.now(),
    chunkCount: 3,
    sha256Hash: 'hash_pipe',
    metadataFileId: 'meta_pipe',
  );

  final chunkMap = <int, ChunkInfo>{
    1: ChunkInfo(index: 1, messageId: 10, fileId: 'chunk_file_1', sizeMb: 19.0),
    2: ChunkInfo(index: 2, messageId: 11, fileId: 'chunk_file_2', sizeMb: 19.0),
    3: ChunkInfo(index: 3, messageId: 12, fileId: 'chunk_file_3', sizeMb: 12.0),
  };

  group('VideoStreamPipeliner Unit Tests', () {
    test('TC-PIPE-01: Streams packets in real-time as they arrive without waiting for full chunk', () async {
      // Simulate a 1 MB chunk arriving in 64 KB packets with delays
      const packetSize = 64 * 1024;
      const totalPackets = 16;
      final fullChunk = Uint8List(packetSize * totalPackets);
      for (int i = 0; i < fullChunk.length; i++) {
        fullChunk[i] = i % 256;
      }

      final streamController = StreamController<List<int>>();

      pipeliner.setStreamFetcherForTesting((fileId, chunkIdx) {
        return streamController.stream;
      });

      final receivedPackets = <Uint8List>[];
      final outputSink = StreamController<List<int>>();
      final streamComplete = Completer<void>();

      outputSink.stream.listen(
        (data) => receivedPackets.add(Uint8List.fromList(data)),
        onDone: () => streamComplete.complete(),
      );

      // Request slice from byte 0 to 128 KB (spans packet 0 and packet 1)
      final pipeFuture = pipeliner.pipeChunkRange(
        record: testRecord,
        chunkIndex: 0,
        sliceStart: 0,
        sliceEnd: (packetSize * 2),
        output: outputSink.sink,
        chunkMap: chunkMap,
      );

      // Emit first packet
      final p0 = fullChunk.sublist(0, packetSize);
      streamController.add(p0);
      await Future.delayed(const Duration(milliseconds: 10));

      // Packet 0 must be forwarded immediately to output before packet 1 is even sent!
      expect(receivedPackets.isNotEmpty, isTrue,
          reason: 'First packet must be forwarded immediately without waiting for chunk completion');
      expect(receivedPackets.first.length, equals(packetSize));

      // Emit remaining packets
      for (int i = 1; i < totalPackets; i++) {
        streamController.add(fullChunk.sublist(i * packetSize, (i + 1) * packetSize));
      }
      await streamController.close();

      await pipeFuture;
      await outputSink.close();
      await streamComplete.future;

      // Total received bytes must equal requested slice (128 KB)
      final totalBytesWritten = receivedPackets.fold(0, (sum, p) => sum + p.length);
      expect(totalBytesWritten, equals(packetSize * 2));
    });

    test('TC-PIPE-02: Accurately slices arbitrary byte windows within packets', () async {
      // 1000 bytes chunk emitted in 100-byte packets
      final chunkBytes = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final stream = Stream.fromIterable([
        for (int i = 0; i < 10; i++) chunkBytes.sublist(i * 100, (i + 1) * 100)
      ]);

      pipeliner.setStreamFetcherForTesting((fileId, chunkIdx) => stream);

      final received = <int>[];
      final sink = StreamController<List<int>>();
      sink.stream.listen(received.addAll);

      // Request bytes 150 to 350 (200 bytes)
      await pipeliner.pipeChunkRange(
        record: testRecord,
        chunkIndex: 0,
        sliceStart: 150,
        sliceEnd: 350,
        output: sink.sink,
        chunkMap: chunkMap,
      );
      await sink.close();

      expect(received.length, equals(200));
      expect(Uint8List.fromList(received), equals(chunkBytes.sublist(150, 350)));
    });

    test('TC-PIPE-03: Concurrently persists streamed chunks to disk cache and hits cache on next read', () async {
      final chunkBytes = Uint8List.fromList(List.generate(5000, (i) => (i * 7) % 256));
      var networkFetchCount = 0;

      pipeliner.setStreamFetcherForTesting((fileId, chunkIdx) {
        networkFetchCount++;
        return Stream.fromIterable([
          chunkBytes.sublist(0, 2500),
          chunkBytes.sublist(2500, 5000),
        ]);
      });

      final sink1 = StreamController<List<int>>();
      sink1.stream.listen((_) {});
      await pipeliner.pipeChunkRange(
        record: testRecord,
        chunkIndex: 1,
        sliceStart: 0,
        sliceEnd: 5000,
        output: sink1.sink,
        chunkMap: chunkMap,
      );
      await sink1.close();

      expect(networkFetchCount, equals(1));

      // Verify cached chunk file exists on disk
      final cachedFile = await VideoChunkCacheManager.instance.getCachedChunk(testRecord.fileId, 1);
      expect(cachedFile, isNotNull);
      expect(cachedFile!.existsSync(), isTrue);
      expect(cachedFile.lengthSync(), equals(5000));

      // Second read should read from disk cache and NOT hit network fetcher
      final received2 = <int>[];
      final sink2 = StreamController<List<int>>();
      sink2.stream.listen(received2.addAll);

      await pipeliner.pipeChunkRange(
        record: testRecord,
        chunkIndex: 1,
        sliceStart: 100,
        sliceEnd: 600,
        output: sink2.sink,
        chunkMap: chunkMap,
      );
      await sink2.close();

      expect(networkFetchCount, equals(1), reason: 'Second read must hit disk cache without network fetch');
      expect(received2.length, equals(500));
      expect(Uint8List.fromList(received2), equals(chunkBytes.sublist(100, 600)));
    });
  });
}
