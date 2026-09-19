/*
 * File: zip_archive_edge_cases_test.dart
 * Description: Edge case tests for ZipArchiveService verifying empty folder handling, cancellation, zero-byte file support, and path disambiguation.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/download_conflict_policy.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/download_service.dart';
import 'package:telstorage/core/services/download_service_contract.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';
import 'package:telstorage/core/services/zip_archive_service.dart';

class _MockDownloadService implements DownloadServiceContract {
  @override
  Future<Uint8List> downloadFile(
    FileRecord file,
    void Function(double progress, String status) onProgress, {
    RequestPriority priority = RequestPriority.normal,
  }) async {
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<SaveResult> downloadFileToDisk(
    FileRecord record,
    void Function(double progress, String status) onProgress, {
    String? subpath,
    DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
    RequestPriority priority = RequestPriority.normal,
    String? explicitTargetPath,
  }) async {
    final bytes = await downloadFile(record, onProgress, priority: priority);
    if (explicitTargetPath != null) {
      final file = File(explicitTargetPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return SaveResult(savedPath: explicitTargetPath, message: 'OK', success: true);
    }
    return SaveResult(savedPath: '/mock/${record.name}', message: 'OK', success: true);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 8, 27);

  group('ZipArchiveService Edge Cases', () {
    test('EC-11: Empty folder export returns null and marks task failed',
        () async {
      final folder = FolderRecord(
          id: 'empty_f', name: 'Empty', parentId: null, createdAt: now);

      final result = await ZipArchiveService.exportFolderAsZip(
        folder: folder,
        items: [],
        downloadService: _MockDownloadService(),
      );

      expect(result, isNull);
      final tasks = TransferQueueService.instance.tasks;
      final matching = tasks.where((t) => t.id.startsWith('zip_empty_f_'));
      expect(matching.isNotEmpty, isTrue);
      expect(matching.first.status, equals(TransferStatus.failed));
      expect(matching.first.currentStage, equals('Folder is empty'));
    });

    test('EC-14: disambiguateArchivePath disambiguates colliding file paths',
        () {
      final usedPaths = <String>{};

      final path1 = ZipArchiveService.disambiguateArchivePath(
          'Work/invoice.pdf', usedPaths);
      final path2 = ZipArchiveService.disambiguateArchivePath(
          'Work/invoice.pdf', usedPaths);
      final path3 = ZipArchiveService.disambiguateArchivePath(
          'Work/invoice.pdf', usedPaths);
      final rootDup1 =
          ZipArchiveService.disambiguateArchivePath('readme.txt', usedPaths);
      final rootDup2 =
          ZipArchiveService.disambiguateArchivePath('readme.txt', usedPaths);

      expect(path1, equals('Work/invoice.pdf'));
      expect(path2, equals('Work/invoice (1).pdf'));
      expect(path3, equals('Work/invoice (2).pdf'));
      expect(rootDup1, equals('readme.txt'));
      expect(rootDup2, equals('readme (1).txt'));
    });

    test('EC-15: createZipFromFiles handles zero-byte files safely', () async {
      final tempDir = await Directory.systemTemp.createTemp('zip_zero_byte_');
      final emptyFile = File('${tempDir.path}/empty.txt')..writeAsBytesSync([]);
      final zipOutput = File('${tempDir.path}/zero.zip');

      await ZipArchiveService.createZipFromFiles(
        destinationZip: zipOutput,
        entries: [
          ZipEntry(file: emptyFile, archivePath: 'empty.txt'),
        ],
      );

      expect(zipOutput.existsSync(), isTrue);
      expect(zipOutput.lengthSync(), greaterThan(0));

      final bytes = zipOutput.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.length, equals(1));
      expect(archive.files.first.name, equals('empty.txt'));
      expect(archive.files.first.size, equals(0));

      await tempDir.delete(recursive: true);
    });

    test('EC-13: isTaskCancelled accurately identifies cancelled status', () {
      final taskId = 'zip_cancel_test_${DateTime.now().millisecondsSinceEpoch}';
      TransferQueueService.instance.addTask(TransferTask(
        id: taskId,
        name: 'test.zip',
        type: TransferType.download,
        sizeMb: 1.0,
        addedAt: now,
        status: TransferStatus.cancelled,
      ));

      expect(ZipArchiveService.isTaskCancelled(taskId), isTrue);
      expect(ZipArchiveService.isTaskCancelled('non_existent_task'), isTrue);
    });
  });
}
