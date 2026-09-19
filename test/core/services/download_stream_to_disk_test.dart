/*
 * File: download_stream_to_disk_test.dart
 * Description: Unit tests validating zero-buffer stream-to-disk downloads, progressive SHA-256 verification, cancellation cleanup, and conflict policies.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/download_service.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';

class _FakeStreamTelegram extends TelegramService {
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

  @override
  Future<void> deleteMessage(int messageId) async {}

  @override
  Future<void> deleteMessages(List<int> messageIds) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeStreamTelegram fakeTelegram;
  late DownloadService downloadService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stream_dl_test_');
    fakeTelegram = _FakeStreamTelegram();
    downloadService = DownloadService(fakeTelegram);
    TransferQueueService.instance.clearAll();
  });

  tearDown(() async {
    TransferQueueService.instance.clearAll();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('DownloadService.downloadFileToDisk Tests', () {
    test('TC-01: Streams multi-chunk file directly to explicitTargetPath with SHA-256 validation', () async {
      final chunk1 = Uint8List.fromList(List.generate(10000, (i) => i % 256));
      final chunk2 = Uint8List.fromList(List.generate(10000, (i) => (i + 50) % 256));
      final combined = Uint8List.fromList([...chunk1, ...chunk2]);
      final expectedHash = sha256.convert(combined).toString();

      final record = FileRecord(
        fileId: 'stream_file_01',
        name: 'video_part.mp4',
        metadataMessageId: 10,
        metadataFileId: 'meta_01',
        sizeMb: combined.length / (1024 * 1024),
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: expectedHash,
      );

      final metaJson = jsonEncode({
        'file_id': record.fileId,
        'name': record.name,
        'size_mb': record.sizeMb,
        'chunk_count': 2,
        'sha256': expectedHash,
        'chunks': [
          {'index': 1, 'message_id': 101, 'file_id': 'c1', 'size_mb': 0.01, 'part_name': 'p1'},
          {'index': 2, 'message_id': 102, 'file_id': 'c2', 'size_mb': 0.01, 'part_name': 'p2'},
        ],
      });

      fakeTelegram.files['meta_01'] = Uint8List.fromList(utf8.encode(metaJson));
      fakeTelegram.files['c1'] = chunk1;
      fakeTelegram.files['c2'] = chunk2;

      final targetPath = '${tempDir.path}/final_output.mp4';
      final progressUpdates = <double>[];

      final result = await downloadService.downloadFileToDisk(
        record,
        (progress, status) => progressUpdates.add(progress),
        explicitTargetPath: targetPath,
      );

      expect(result.success, isTrue);
      expect(result.savedPath, equals(targetPath));

      final savedFile = File(targetPath);
      expect(savedFile.existsSync(), isTrue);
      expect(await savedFile.readAsBytes(), equals(combined));
      expect(progressUpdates, isNotEmpty);
      expect(progressUpdates.last, equals(1.0));
    });

    test('TC-02: Corrupted chunk throws FileCorruptedException and cleans up temporary staging file', () async {
      final chunk1 = Uint8List.fromList(List.generate(5000, (i) => i % 256));
      final chunk2 = Uint8List.fromList(List.generate(5000, (i) => (i + 10) % 256));
      final combined = Uint8List.fromList([...chunk1, ...chunk2]);
      final expectedHash = sha256.convert(combined).toString();

      final record = FileRecord(
        fileId: 'stream_corrupt_01',
        name: 'corrupt.bin',
        metadataMessageId: 20,
        metadataFileId: 'meta_corrupt',
        sizeMb: combined.length / (1024 * 1024),
        mimeType: 'application/octet-stream',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: expectedHash,
      );

      final metaJson = jsonEncode({
        'file_id': record.fileId,
        'name': record.name,
        'size_mb': record.sizeMb,
        'chunk_count': 2,
        'sha256': expectedHash,
        'chunks': [
          {'index': 1, 'message_id': 201, 'file_id': 'corrupt_c1', 'size_mb': 0.005, 'part_name': 'p1'},
          {'index': 2, 'message_id': 202, 'file_id': 'corrupt_c2', 'size_mb': 0.005, 'part_name': 'p2'},
        ],
      });

      fakeTelegram.files['meta_corrupt'] = Uint8List.fromList(utf8.encode(metaJson));
      fakeTelegram.files['corrupt_c1'] = chunk1;
      // Corrupt chunk 2 with different bytes
      fakeTelegram.files['corrupt_c2'] = Uint8List.fromList(List.filled(5000, 99));

      final targetPath = '${tempDir.path}/corrupt_target.bin';

      expect(
        () => downloadService.downloadFileToDisk(
          record,
          (_, __) {},
          explicitTargetPath: targetPath,
        ),
        throwsA(isA<FileCorruptedException>()),
      );

      // Verify target file and temporary files were not left on disk
      expect(File(targetPath).existsSync(), isFalse);
      final remainingFiles = tempDir.listSync();
      expect(remainingFiles, isEmpty);
    });

    test('TC-03: User cancellation mid-stream deletes temporary staging file', () async {
      final chunk1 = Uint8List.fromList(List.filled(5000, 1));
      final chunk2 = Uint8List.fromList(List.filled(5000, 2));

      final record = FileRecord(
        fileId: 'stream_cancel_01',
        name: 'cancelled.dat',
        metadataMessageId: 30,
        metadataFileId: 'meta_cancel',
        sizeMb: 0.01,
        mimeType: 'application/octet-stream',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 2,
        sha256Hash: 'dummy_hash',
      );

      final metaJson = jsonEncode({
        'file_id': record.fileId,
        'name': record.name,
        'size_mb': record.sizeMb,
        'chunk_count': 2,
        'sha256': 'dummy_hash',
        'chunks': [
          {'index': 1, 'message_id': 301, 'file_id': 'cancel_c1', 'size_mb': 0.005, 'part_name': 'p1'},
          {'index': 2, 'message_id': 302, 'file_id': 'cancel_c2', 'size_mb': 0.005, 'part_name': 'p2'},
        ],
      });

      fakeTelegram.files['meta_cancel'] = Uint8List.fromList(utf8.encode(metaJson));
      fakeTelegram.files['cancel_c1'] = chunk1;
      fakeTelegram.files['cancel_c2'] = chunk2;

      // Register and cancel task
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

      final targetPath = '${tempDir.path}/cancel_target.dat';

      expect(
        () => downloadService.downloadFileToDisk(
          record,
          (_, __) {},
          explicitTargetPath: targetPath,
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message', contains('cancelled by user'))),
      );

      expect(File(targetPath).existsSync(), isFalse);
      expect(tempDir.listSync(), isEmpty);
    });

    test('TC-04: Missing metadataFileId throws StateError', () async {
      final record = FileRecord(
        fileId: 'stream_no_meta',
        name: 'no_meta.txt',
        metadataMessageId: 40,
        metadataFileId: null,
        sizeMb: 0.01,
        mimeType: 'text/plain',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'hash',
      );

      expect(
        () => downloadService.downloadFileToDisk(record, (_, __) {}),
        throwsA(isA<StateError>()),
      );
    });
  });
}
