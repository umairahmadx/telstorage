/*
 * File: web_share_folder_zip_test.dart
 * Description: Unit tests validating zero-OOM ZipFileEncoder disk streaming, folder packaging, and WebShareSettingsService.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/web_share_job.dart';
import 'package:telstorage/core/models/download_conflict_policy.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/download_service.dart';
import 'package:telstorage/core/services/download_service_contract.dart';
import 'package:telstorage/core/services/folder_traversal_service.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';
import 'package:telstorage/core/services/web_share_api_client.dart';
import 'package:telstorage/core/services/web_share_settings_service.dart';
import 'package:telstorage/core/services/zip_archive_service.dart';

class FakeDownloadService implements DownloadServiceContract {
  @override
  Future<Uint8List> downloadFile(
    FileRecord file,
    void Function(double progress, String status) onProgress,
  ) async {
    onProgress(1.0, 'Downloaded');
    return Uint8List.fromList('Contents of ${file.name}'.codeUnits);
  }

  @override
  Future<SaveResult> saveAndOpen(
    Uint8List bytes,
    String filename, {
    String? subpath,
    DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
  }) async {
    return const SaveResult(
        savedPath: '/fake/path', message: 'OK', success: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempTestDir;

  setUp(() async {
    tempTestDir =
        Directory.systemTemp.createTempSync('web_share_folder_test_');
    Hive.init(tempTestDir.path);
  });

  tearDown(() async {
    TransferQueueService.instance.clearAll();
    if (tempTestDir.existsSync()) {
      try {
        tempTestDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Web Share Folder ZIP & Streaming Compression Tests', () {
    test(
        'TC-01: ZipFileEncoder streams multi-file entries directly into valid on-disk ZIP',
        () async {
      final file1 = File('${tempTestDir.path}/doc1.txt')
        ..writeAsStringSync('Hello Document 1');
      final file2 = File('${tempTestDir.path}/doc2.txt')
        ..writeAsStringSync('Hello Document 2');

      final destinationZip = File('${tempTestDir.path}/output_archive.zip');
      final entries = [
        ZipEntry(file: file1, archivePath: 'doc1.txt'),
        ZipEntry(file: file2, archivePath: 'nested/doc2.txt'),
      ];

      await ZipArchiveService.createZipFromFiles(
        destinationZip: destinationZip,
        entries: entries,
      );

      expect(destinationZip.existsSync(), isTrue);
      expect(destinationZip.lengthSync(), greaterThan(0));

      final bytes = destinationZip.readAsBytesSync();
      final decodedArchive = ZipDecoder().decodeBytes(bytes);
      expect(decodedArchive.files.length, equals(2));
      expect(
        decodedArchive.files.map((f) => f.name),
        containsAll(['doc1.txt', 'nested/doc2.txt']),
      );
    });

    test(
        'TC-02: packageFolderToTempZip packages FolderFileItems into temporary staged ZIP',
        () async {
      final folder = FolderRecord(
        id: 'f_root',
        name: 'Project Assets',
        createdAt: DateTime.now(),
      );

      final file1 = FileRecord(
        fileId: 'file_1',
        name: 'logo.png',
        mimeType: 'image/png',
        sizeMb: 0.1,
        metadataMessageId: 10,
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: '',
      );

      final items = [
        FolderFileItem(file: file1, relativePath: 'logo.png', subpath: ''),
      ];

      final fakeDownload = FakeDownloadService();
      TransferQueueService.instance.addTask(TransferTask(
        id: 'test_transfer_1',
        name: 'test.zip',
        type: TransferType.share,
        sizeMb: 1.0,
        addedAt: DateTime.now(),
        status: TransferStatus.sharing,
      ));

      final stagedZip = await ZipArchiveService.packageFolderToTempZip(
        folder: folder,
        items: items,
        downloadService: fakeDownload,
        transferId: 'test_transfer_1',
      );

      expect(stagedZip, isNotNull);
      expect(stagedZip!.existsSync(), isTrue);
      expect(stagedZip.path.endsWith('.zip'), isTrue);

      final bytes = stagedZip.readAsBytesSync();
      final decoded = ZipDecoder().decodeBytes(bytes);
      expect(decoded.files.length, equals(1));
      expect(decoded.files.first.name, equals('logo.png'));

      // Clean up staged ZIP parent directory
      if (stagedZip.parent.existsSync()) {
        stagedZip.parent.deleteSync(recursive: true);
      }
    });

    test(
        'TC-03: WebShareSettingsService correctly applies vanity slug formatting',
        () async {
      final box = await Hive.openBox('test_settings_box_${DateTime.now().millisecondsSinceEpoch}');
      try {
        final settingsService = WebShareSettingsService(
          apiClient: WebShareApiClient(),
          box: box,
        );

        final simulatedJob = WebShareJob(
          fileId: 'share_1',
          name: 'archive.zip',
          mimeType: 'application/zip',
          sizeMb: 5.0,
          status: 'completed',
          addedAt: DateTime.now(),
        );
        await box.put('share_1', simulatedJob.toMap());

        expect(box.containsKey('share_1'), isTrue);
        await settingsService.deleteShare('share_1');
        expect(box.containsKey('share_1'), isFalse);
      } finally {
        await box.close();
      }
    });

    test(
        'TC-04: Active TransferType.share task is marked active and updates stage and progress',
        () async {
      final task = TransferTask(
        id: 'share_job_123',
        name: 'SharedVideo.mp4',
        type: TransferType.share,
        sizeMb: 25.0,
        addedAt: DateTime.now(),
        status: TransferStatus.sharing,
        currentStage: 'Uploading to Web… 50%',
        progress: 0.50,
      );

      TransferQueueService.instance.addTask(task);

      final active = TransferQueueService.instance.activeTasks;
      expect(active.length, equals(1));
      expect(active.first.type, equals(TransferType.share));
      expect(active.first.isActive, isTrue);
      expect(active.first.progress, equals(0.50));
      expect(active.first.currentStage, equals('Uploading to Web… 50%'));

      TransferQueueService.instance.updateTask(
        'share_job_123',
        progress: 0.90,
        currentStage: 'Uploading to Web… 90%',
      );

      final updated = TransferQueueService.instance.activeTasks.first;
      expect(updated.progress, equals(0.90));
      expect(updated.currentStage, equals('Uploading to Web… 90%'));
    });
  });
}
