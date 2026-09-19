/*
 * File: download_service_test.dart
 * Description: Unit tests for DownloadService verifying multi-chunk raw download reassembly, SHA-256 verification, and cancellation.
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/download_service.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeDownloadTelegram fakeTelegram;
  late DownloadService downloadService;

  setUp(() {
    fakeTelegram = FakeDownloadTelegram();
    downloadService = DownloadService(fakeTelegram);
    TransferQueueService.instance.clearAll();
  });

  tearDown(() {
    TransferQueueService.instance.clearAll();
  });

  group('DownloadService Raw Multi-Chunk Tests', () {
    test('Downloads and reassembles multi-chunk raw file and verifies SHA-256', () async {
      final rawPayload = Uint8List.fromList(List.generate(50000, (i) => (i * 11) % 256));
      final expectedSha = sha256.convert(rawPayload).toString();

      const partSize = 20000;
      final part1 = Uint8List.sublistView(rawPayload, 0, partSize);
      final part2 = Uint8List.sublistView(rawPayload, partSize, partSize * 2);
      final part3 = Uint8List.sublistView(rawPayload, partSize * 2);

      final record = FileRecord(
        fileId: 'dl_raw_file_1',
        name: 'big_archive.tar',
        metadataMessageId: 200,
        metadataFileId: 'meta_tar_id',
        sizeMb: rawPayload.length / (1024 * 1024),
        mimeType: 'application/x-tar',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 3,
        sha256Hash: expectedSha,
      );

      final metadataJson = jsonEncode({
        'file_id': record.fileId,
        'name': record.name,
        'size_mb': record.sizeMb,
        'chunk_count': 3,
        'sha256': expectedSha,
        'chunks': [
          {'index': 1, 'message_id': 201, 'file_id': 'part_1_id', 'size_mb': 0.02, 'part_name': 'big_archive.tar.001'},
          {'index': 2, 'message_id': 202, 'file_id': 'part_2_id', 'size_mb': 0.02, 'part_name': 'big_archive.tar.002'},
          {'index': 3, 'message_id': 203, 'file_id': 'part_3_id', 'size_mb': 0.01, 'part_name': 'big_archive.tar.003'},
        ],
      });

      fakeTelegram.files['meta_tar_id'] = Uint8List.fromList(utf8.encode(metadataJson));
      fakeTelegram.files['part_1_id'] = part1;
      fakeTelegram.files['part_2_id'] = part2;
      fakeTelegram.files['part_3_id'] = part3;

      final progressUpdates = <double>[];
      final downloadedBytes = await downloadService.downloadFile(
        record,
        (progress, status) => progressUpdates.add(progress),
      );

      expect(downloadedBytes, equals(rawPayload));
      expect(progressUpdates, isNotEmpty);
      expect(progressUpdates.last, equals(1.0));
    });

    test('Throws FileCorruptedException when SHA-256 digest does not match metadata', () async {
      final rawPayload = Uint8List.fromList(List.generate(1000, (i) => i % 256));
      final actualSha = sha256.convert(rawPayload).toString();
      const corruptedExpectedSha = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

      final record = FileRecord(
        fileId: 'dl_corrupt_file',
        name: 'corrupt.bin',
        metadataMessageId: 210,
        metadataFileId: 'meta_corrupt_id',
        sizeMb: 0.001,
        mimeType: 'application/octet-stream',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: actualSha,
      );

      final metadataJson = jsonEncode({
        'file_id': record.fileId,
        'name': record.name,
        'size_mb': record.sizeMb,
        'chunk_count': 1,
        'sha256': corruptedExpectedSha,
        'chunks': [
          {'index': 1, 'message_id': 211, 'file_id': 'part_c1', 'size_mb': 0.001, 'part_name': 'corrupt.bin.001'},
        ],
      });

      fakeTelegram.files['meta_corrupt_id'] = Uint8List.fromList(utf8.encode(metadataJson));
      fakeTelegram.files['part_c1'] = rawPayload;

      expect(
        () => downloadService.downloadFile(record, (_, __) {}),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('File integrity check failed'))),
      );
    });

    test('Aborts download immediately when user cancels via TransferQueueService', () async {
      final rawPayload = Uint8List.fromList(List.generate(2000, (i) => i % 256));
      final sha = sha256.convert(rawPayload).toString();

      final record = FileRecord(
        fileId: 'cancel_file_id',
        name: 'cancelled.mp4',
        metadataMessageId: 220,
        metadataFileId: 'meta_cancel_id',
        sizeMb: 0.002,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: sha,
      );

      final metadataJson = jsonEncode({
        'file_id': record.fileId,
        'name': record.name,
        'size_mb': record.sizeMb,
        'chunk_count': 2,
        'sha256': sha,
        'chunks': [
          {'index': 1, 'message_id': 221, 'file_id': 'p1', 'size_mb': 0.001, 'part_name': 'part.001'},
          {'index': 2, 'message_id': 222, 'file_id': 'p2', 'size_mb': 0.001, 'part_name': 'part.002'},
        ],
      });

      fakeTelegram.files['meta_cancel_id'] = Uint8List.fromList(utf8.encode(metadataJson));
      fakeTelegram.files['p1'] = Uint8List(1000);
      fakeTelegram.files['p2'] = Uint8List(1000);

      // Pre-cancel the file via TransferQueueService
      TransferQueueService.instance.addTask(TransferTask(
        id: record.fileId,
        name: record.name,
        type: TransferType.download,
        sizeMb: record.sizeMb,
        progress: 0.0,
        status: TransferStatus.downloading,
        addedAt: DateTime.now(),
      ));
      TransferQueueService.instance.cancelTask(record.fileId);

      expect(
        () => downloadService.downloadFile(record, (_, __) {}),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('cancelled by user'))),
      );
    });
  });
}

class FakeDownloadTelegram extends TelegramService {
  final Map<String, Uint8List> files = {};

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
    CancelToken? cancelToken,
  ]) async {
    final data = files[fileId];
    if (data != null) return data;
    throw Exception('File not found: $fileId');
  }
}
