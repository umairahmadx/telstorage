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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pipeliner_test_');
    VideoChunkCacheManager.instance.setBaseDirForTesting(tempDir);
  });

  tearDown(() async {
    VideoChunkCacheManager.instance.setBaseDirForTesting(null);
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('pipeChunkRange resolves as soon as requested slice is written without waiting for full stream to end', () async {
    final pipeliner = VideoStreamPipeliner();
    final streamController = StreamController<List<int>>();

    pipeliner.setStreamFetcherForTesting((fileId, chunkIndex) {
      return streamController.stream;
    });

    final record = FileRecord(
      fileId: 'test_file_id',
      name: 'video.mp4',
      metadataMessageId: 0,
      sizeMb: 50.0,
      mimeType: 'video/mp4',
      uploadedAt: DateTime.now(),
      chunkCount: 3,
      sha256Hash: 'dummy',
    );

    final outputSink = StreamController<List<int>>();
    outputSink.stream.listen((_) {});

    // Requesting bytes 0 to 1024 (1 KB slice of chunk 0)
    final pipeFuture = pipeliner.pipeChunkRange(
      record: record,
      chunkIndex: 0,
      sliceStart: 0,
      sliceEnd: 1024,
      output: outputSink,
    );

    // Allow pipeChunkRange async setup to register subscription
    await pumpEventQueue();
    streamController.add(Uint8List(2048));

    final bytesWritten = await pipeFuture.timeout(const Duration(seconds: 1));
    expect(bytesWritten, equals(1024));

    await streamController.close();
    await outputSink.close();
  });

  test('resolveChunkFileId correctly handles 0-based and 1-based chunk maps', () {
    final pipeliner = VideoStreamPipeliner();
    final record = FileRecord(
      fileId: 'rec_id',
      name: 'vid.mkv',
      metadataMessageId: 0,
      sizeMb: 50.0,
      mimeType: 'video/x-matroska',
      uploadedAt: DateTime.now(),
      chunkCount: 2,
      sha256Hash: 'dummy',
    );

    // 0-based map: {0: chunkA, 1: chunkB}
    final zeroBasedMap = {
      0: ChunkInfo(index: 0, fileId: 'zero_chunk_0', sizeMb: 25.0, messageId: 1),
      1: ChunkInfo(index: 1, fileId: 'zero_chunk_1', sizeMb: 25.0, messageId: 2),
    };

    expect(
      pipeliner.resolveChunkFileIdForTesting(record, 0, zeroBasedMap),
      equals('zero_chunk_0'),
    );
    expect(
      pipeliner.resolveChunkFileIdForTesting(record, 1, zeroBasedMap),
      equals('zero_chunk_1'),
    );

    // 1-based map: {1: chunkA, 2: chunkB}
    final oneBasedMap = {
      1: ChunkInfo(index: 1, fileId: 'one_chunk_1', sizeMb: 25.0, messageId: 1),
      2: ChunkInfo(index: 2, fileId: 'one_chunk_2', sizeMb: 25.0, messageId: 2),
    };

    expect(
      pipeliner.resolveChunkFileIdForTesting(record, 0, oneBasedMap),
      equals('one_chunk_1'),
    );
    expect(
      pipeliner.resolveChunkFileIdForTesting(record, 1, oneBasedMap),
      equals('one_chunk_2'),
    );
  });
}
