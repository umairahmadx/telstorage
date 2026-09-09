/*
 * File: video_stream_metadata_validation_test.dart
 * Description: Unit tests for VideoStreamServer metadata validation and chunk mapping rules.
 * Verifies 1-based indexing, out-of-order chunk handling, and corrupted metadata rejection.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VideoStreamServer server;
  late Directory tempDir;

  setUp(() async {
    HttpOverrides.global = null;
    tempDir = await Directory.systemTemp.createTemp('vss_meta_val_test_');
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

  group('VideoStreamServer Metadata Validation Tests', () {
    test(
      'TC-VSS-09: 1-based chunks correctly mapped even if metadata array is out of order',
      () async {
        final chunk1Bytes = Uint8List.fromList(List.generate(100, (i) => 10));
        final chunk2Bytes = Uint8List.fromList(List.generate(100, (i) => 20));
        final testRecord = FileRecord(
          fileId: 'stream_vid_unsorted_1',
          name: 'movie_multi.mp4',
          metadataMessageId: 40,
          metadataFileId: 'meta_unsorted_id',
          sizeMb: 200 / (1024 * 1024),
          mimeType: 'video/mp4',
          uploadedAt: DateTime(2026, 1, 1),
          chunkCount: 2,
          sha256Hash: 'dummy_unsorted',
        );

        // Metadata with reversed chunk order: index 2 is listed BEFORE index 1
        final metadataJson = jsonEncode({
          'file_id': testRecord.fileId,
          'name': testRecord.name,
          'size_mb': testRecord.sizeMb,
          'chunk_count': 2,
          'chunks': [
            {
              'index': 2,
              'message_id': 42,
              'file_id': 'tg_chunk_002',
              'size_mb': 100 / (1024 * 1024),
              'part_name': 'part2',
            },
            {
              'index': 1,
              'message_id': 41,
              'file_id': 'tg_chunk_001',
              'size_mb': 100 / (1024 * 1024),
              'part_name': 'part1',
            },
          ],
        });

        final fakeTelegram = _FakeStreamTelegramService();
        fakeTelegram.files['meta_unsorted_id'] =
            Uint8List.fromList(utf8.encode(metadataJson));
        fakeTelegram.files['tg_chunk_001'] = chunk1Bytes;
        fakeTelegram.files['tg_chunk_002'] = chunk2Bytes;

        ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
        ServiceLocator.instance.setInitializedForTesting(true);

        server.registerFile(testRecord);
        server.setChunkFetcherForTesting(null);

        await server.start();
        final client = HttpClient();
        try {
          final streamUrl = server.getStreamUrl(testRecord.fileId);
          // Request byte 0: should map to chunk 0 -> metadata index 1 -> tg_chunk_001
          final request1 = await client.getUrl(Uri.parse(streamUrl));
          request1.headers.set(HttpHeaders.rangeHeader, 'bytes=0-9');
          final response1 = await request1.close();
          final bytes1 = await response1.fold<List<int>>(
            [],
            (prev, elem) => prev..addAll(elem),
          );
          expect(bytes1.every((b) => b == 10), isTrue);
        } finally {
          client.close();
          ServiceLocator.instance.setInitializedForTesting(false);
        }
      },
    );

    test(
      'TC-VSS-10: missing chunk in metadata fails fast with HTTP 500 without serving corrupt bytes',
      () async {
        final testRecord = FileRecord(
          fileId: 'stream_vid_corrupt_1',
          name: 'corrupt.mp4',
          metadataMessageId: 50,
          metadataFileId: 'meta_corrupt_id',
          sizeMb: 200 / (1024 * 1024),
          mimeType: 'video/mp4',
          uploadedAt: DateTime(2026, 1, 1),
          chunkCount: 2,
          sha256Hash: 'dummy_corrupt',
        );

        // Metadata has chunk 1, but chunk 2 is missing!
        final metadataJson = jsonEncode({
          'file_id': testRecord.fileId,
          'name': testRecord.name,
          'size_mb': testRecord.sizeMb,
          'chunk_count': 2,
          'chunks': [
            {
              'index': 1,
              'message_id': 51,
              'file_id': 'tg_chunk_only_1',
              'size_mb': 100 / (1024 * 1024),
              'part_name': 'part1',
            },
          ],
        });

        final fakeTelegram = _FakeStreamTelegramService();
        fakeTelegram.files['meta_corrupt_id'] =
            Uint8List.fromList(utf8.encode(metadataJson));
        fakeTelegram.files['tg_chunk_only_1'] = Uint8List(100);

        ServiceLocator.instance.setTelegramForTesting(fakeTelegram);
        ServiceLocator.instance.setInitializedForTesting(true);

        server.registerFile(testRecord);
        server.setChunkFetcherForTesting(null);

        await server.start();
        final client = HttpClient();
        try {
          final streamUrl = server.getStreamUrl(testRecord.fileId);
          final request = await client.getUrl(Uri.parse(streamUrl));
          final response = await request.close();
          // Validation fails because chunk 2 is missing -> HTTP 500 error, never corrupt data
          expect(response.statusCode, equals(HttpStatus.internalServerError));
          await response.drain();
        } finally {
          client.close();
          ServiceLocator.instance.setInitializedForTesting(false);
        }
      },
    );
  });
}

class _FakeStreamTelegramService extends TelegramService {
  final Map<String, Uint8List> files = {};
  int downloadCallCount = 0;

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
  ]) async {
    downloadCallCount++;
    final data = files[fileId];
    if (data != null) return data;
    throw Exception('File not found in fake telegram: $fileId');
  }
}
