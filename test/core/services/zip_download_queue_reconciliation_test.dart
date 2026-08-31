/*
 * File: zip_download_queue_reconciliation_test.dart
 * Description: Unit tests validating ZIP download queue integration, mutual exclusion in completed downloads, cancellation synchronization, failure resilience, and disk cleanup.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/download_job.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/download_queue_service.dart';
import 'package:telstorage/core/services/download_service.dart';
import 'package:telstorage/core/services/download_service_contract.dart';
import 'package:telstorage/core/services/folder_traversal_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';
import 'package:telstorage/core/services/zip_archive_service.dart';
import 'package:telstorage/core/utils/connectivity.dart';

class _MockDownloadService implements DownloadServiceContract {
  final Future<Uint8List> Function(FileRecord file)? customDownload;

  _MockDownloadService({this.customDownload});

  @override
  Future<Uint8List> downloadFile(
    FileRecord file,
    void Function(double progress, String status) onProgress,
  ) async {
    if (customDownload != null) {
      return await customDownload!(file);
    }
    return Uint8List.fromList([1, 2, 3, 4, 5]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingDownloadQueueService extends DownloadQueueService {
  final bool failOnStart;
  final bool failOnComplete;

  _FailingDownloadQueueService(
    super.downloadService,
    super.boxName, {
    this.failOnStart = false,
    this.failOnComplete = false,
  });

  @override
  Future<void> addOrUpdateZipJob({
    required String fileId,
    required String name,
    required String mimeType,
    required double sizeMb,
    required String status,
    double progress = 0.0,
    String? localPath,
    String? error,
    DateTime? addedAt,
    DateTime? completedAt,
    String? subpath,
  }) async {
    if (failOnStart && status == 'downloading') {
      throw Exception('Simulated Hive box start write failure');
    }
    if (failOnComplete && status == 'completed') {
      throw Exception('Simulated Hive box completion write failure');
    }
    await super.addOrUpdateZipJob(
      fileId: fileId,
      name: name,
      mimeType: mimeType,
      sizeMb: sizeMb,
      status: status,
      progress: progress,
      localPath: localPath,
      error: error,
      addedAt: addedAt,
      completedAt: completedAt,
      subpath: subpath,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempHiveDir;
  late Box<DownloadJob> downloadsBox;
  late DownloadQueueService downloadQueueService;
  final now = DateTime(2026, 8, 27);

  setUpAll(() async {
    tempHiveDir = await Directory.systemTemp
        .createTemp('zip_reconciliation_test_hive_');
    Hive.init(tempHiveDir.path);
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(DownloadJobAdapter());
    }
    Connectivity.mockConnectionStatus = true;
  });

  tearDownAll(() async {
    Connectivity.mockConnectionStatus = null;
    await Hive.close();
    if (tempHiveDir.existsSync()) {
      await tempHiveDir.delete(recursive: true);
    }
  });

  setUp(() async {
    TransferQueueService.instance.clear();
    downloadsBox =
        await Hive.openBox<DownloadJob>(AppConstants.downloadsBox);
    await downloadsBox.clear();

    final dummyTelegram = TelegramService();
    final downloadService = DownloadService(dummyTelegram);
    downloadQueueService =
        DownloadQueueService(downloadService, AppConstants.downloadsBox);

    ServiceLocator.instance.setDownloadQueueForTesting(downloadQueueService);
    ServiceLocator.instance.setInitializedForTesting(true);
  });

  tearDown(() async {
    await downloadsBox.clear();
    ServiceLocator.instance.setInitializedForTesting(false);
  });

  group('ZIP & Download Queue Reconciliation & Mutual Exclusion Tests', () {
    test('Test 1: Premature display prevention — in-progress download is excluded from completed',
        () {
      final activeJob = DownloadJob(
        fileId: 'file_in_progress_1',
        name: 'video.mp4',
        mimeType: 'video/mp4',
        sizeMb: 50.0,
        status: 'downloading',
        progress: 0.45,
        addedAt: now,
      );

      final completedJob = DownloadJob(
        fileId: 'file_completed_1',
        name: 'document.pdf',
        mimeType: 'application/pdf',
        sizeMb: 2.0,
        status: 'completed',
        progress: 1.0,
        localPath: '/downloads/document.pdf',
        addedAt: now,
        completedAt: now,
      );

      final allJobs = [activeJob, completedJob];

      // Simulate DownloadsScreen filtering
      final activeTransfers = [
        TransferTask(
          id: activeJob.fileId,
          name: activeJob.name,
          type: TransferType.download,
          sizeMb: activeJob.sizeMb,
          status: TransferStatus.downloading,
          progress: activeJob.progress,
          addedAt: now,
        ),
      ];

      final activeIds = activeTransfers.map((t) => t.id).toSet();

      final completedDownloads = allJobs.where((j) {
        if (!j.isComplete) return false;
        if (activeIds.contains(j.fileId)) return false;
        return true;
      }).toList();

      expect(completedDownloads.length, equals(1));
      expect(completedDownloads.first.fileId, equals('file_completed_1'));
      expect(completedDownloads.any((j) => j.fileId == 'file_in_progress_1'),
          isFalse);
    });

    test(
        'Test 2: Adversarial timing & Mutual exclusion — active task prevents duplicate in completed until flip',
        () {
      const targetId = 'shared_job_race_id';

      // Simulate state where Hive was marked completed first, but TransferTask is still active
      final raceJob = DownloadJob(
        fileId: targetId,
        name: 'archive.zip',
        mimeType: 'application/zip',
        sizeMb: 10.0,
        status: 'completed',
        progress: 1.0,
        localPath: '/downloads/archive.zip',
        addedAt: now,
        completedAt: now,
      );

      final activeTask = TransferTask(
        id: targetId,
        name: 'archive.zip',
        type: TransferType.download,
        sizeMb: 10.0,
        status: TransferStatus.downloading, // Still active in memory
        progress: 0.99,
        addedAt: now,
      );

      // Frame 1: Active task is active -> Mutual exclusion filter MUST exclude it from completed
      var activeTransfers = [activeTask];
      var activeIds = activeTransfers.map((t) => t.id).toSet();

      var completedDownloads = [raceJob].where((j) {
        if (!j.isComplete) return false;
        if (activeIds.contains(j.fileId)) return false;
        return true;
      }).toList();

      expect(completedDownloads, isEmpty,
          reason: 'Must not appear in completed while active in memory');

      // Frame 2: TransferTask flips to completed (isActive == false)
      activeTask.status = TransferStatus.completed;
      activeTransfers = [activeTask].where((t) => t.isActive).toList();
      activeIds = activeTransfers.map((t) => t.id).toSet();

      completedDownloads = [raceJob].where((j) {
        if (!j.isComplete) return false;
        if (activeIds.contains(j.fileId)) return false;
        return true;
      }).toList();

      expect(completedDownloads.length, equals(1));
      expect(completedDownloads.first.fileId, equals(targetId));
    });

    test('Test 3: Full ZIP lifecycle into Completed Downloads', () async {
      final folder = FolderRecord(
        id: 'folder_photo_1',
        name: 'Holiday Photos',
        parentId: null,
        createdAt: now,
      );

      final file1 = FileRecord(
        fileId: 'photo_1',
        metadataMessageId: 10,
        metadataFileId: 'meta_1',
        name: 'beach.jpg',
        sizeMb: 1.5,
        mimeType: 'image/jpeg',
        uploadedAt: now,
        chunkCount: 1,
        sha256Hash: 'hash1',
      );

      final items = [
        FolderFileItem(file: file1, subpath: '', relativePath: 'beach.jpg'),
      ];

      final savedPath = await ZipArchiveService.exportFolderAsZip(
        folder: folder,
        items: items,
        downloadService: _MockDownloadService(),
      );

      expect(savedPath, isNotNull);

      // Verify DownloadJob was created in Hive
      final allJobs = downloadQueueService.allJobs;
      expect(allJobs.isNotEmpty, isTrue);

      final zipJob = allJobs.first;
      expect(zipJob.name, equals('Holiday Photos.zip'));
      expect(zipJob.status, equals('completed'));
      expect(zipJob.progress, equals(1.0));
      expect(zipJob.localPath, equals(savedPath));
      expect(zipJob.isComplete, isTrue);

      // Verify TransferTask is completed
      final activeTasks = TransferQueueService.instance.activeTasks;
      expect(activeTasks.where((t) => t.id == zipJob.fileId), isEmpty);

      // Verify UI completed filtering
      final activeIds = activeTasks.map((t) => t.id).toSet();
      final completedDownloads = allJobs.where((j) {
        if (!j.isComplete) return false;
        if (activeIds.contains(j.fileId)) return false;
        return true;
      }).toList();

      expect(completedDownloads.length, equals(1));
      expect(completedDownloads.first.name, equals('Holiday Photos.zip'));
    });

    test('Test 4: Cancellation cleanup in both services', () async {
      final folder = FolderRecord(
        id: 'folder_cancel_1',
        name: 'Large Backup',
        parentId: null,
        createdAt: now,
      );

      final file1 = FileRecord(
        fileId: 'bk_1',
        metadataMessageId: 20,
        metadataFileId: 'meta_2',
        name: 'backup.bin',
        sizeMb: 100.0,
        mimeType: 'application/octet-stream',
        uploadedAt: now,
        chunkCount: 1,
        sha256Hash: 'hash2',
      );

      final items = [
        FolderFileItem(file: file1, subpath: '', relativePath: 'backup.bin'),
      ];

      final mockService = _MockDownloadService(
        customDownload: (file) async {
          // Cancel during download
          final active = TransferQueueService.instance.tasks;
          final matching = active.where((t) => t.id.startsWith('zip_folder_cancel_1_'));
          if (matching.isNotEmpty) {
            TransferQueueService.instance.cancelTask(matching.first.id);
          }
          return Uint8List.fromList([1, 2, 3]);
        },
      );

      final result = await ZipArchiveService.exportFolderAsZip(
        folder: folder,
        items: items,
        downloadService: mockService,
      );

      expect(result, isNull);

      final allJobs = downloadQueueService.allJobs;
      final matchingJob =
          allJobs.where((j) => j.fileId.startsWith('zip_folder_cancel_1_')).firstOrNull;

      expect(matchingJob, isNotNull);
      expect(matchingJob!.status, equals('cancelled'));

      final task = TransferQueueService.instance.tasks
          .firstWhere((t) => t.id.startsWith('zip_folder_cancel_1_'));
      expect(task.status, equals(TransferStatus.cancelled));
      expect(task.isActive, isFalse);
    });

    test('Test 5: Hive completion write failure resilience — keeps task visible as failed',
        () async {
      final failingQueue = _FailingDownloadQueueService(
        DownloadService(TelegramService()),
        AppConstants.downloadsBox,
        failOnComplete: true,
      );

      ServiceLocator.instance.setDownloadQueueForTesting(failingQueue);

      final folder = FolderRecord(
        id: 'folder_fail_complete_1',
        name: 'Faulty Folder',
        parentId: null,
        createdAt: now,
      );

      final file1 = FileRecord(
        fileId: 'f_1',
        metadataMessageId: 30,
        metadataFileId: 'meta_3',
        name: 'test.txt',
        sizeMb: 1.0,
        mimeType: 'text/plain',
        uploadedAt: now,
        chunkCount: 1,
        sha256Hash: 'hash3',
      );

      final items = [
        FolderFileItem(file: file1, subpath: '', relativePath: 'test.txt'),
      ];

      final result = await ZipArchiveService.exportFolderAsZip(
        folder: folder,
        items: items,
        downloadService: _MockDownloadService(),
      );

      expect(result, isNull);

      final tasks = TransferQueueService.instance.tasks
          .where((t) => t.id.startsWith('zip_folder_fail_complete_1_'));
      expect(tasks.isNotEmpty, isTrue);
      expect(tasks.first.status, equals(TransferStatus.failed));
      expect(tasks.first.error, contains('Failed to save download record'));
    });

    test('Test 6: Start-write failure guard — aborts immediately and marks task failed',
        () async {
      final failingQueue = _FailingDownloadQueueService(
        DownloadService(TelegramService()),
        AppConstants.downloadsBox,
        failOnStart: true,
      );

      ServiceLocator.instance.setDownloadQueueForTesting(failingQueue);

      final folder = FolderRecord(
        id: 'folder_fail_start_1',
        name: 'Aborted Folder',
        parentId: null,
        createdAt: now,
      );

      final file1 = FileRecord(
        fileId: 'f_start_1',
        metadataMessageId: 40,
        metadataFileId: 'meta_4',
        name: 'test.txt',
        sizeMb: 1.0,
        mimeType: 'text/plain',
        uploadedAt: now,
        chunkCount: 1,
        sha256Hash: 'hash4',
      );

      final items = [
        FolderFileItem(file: file1, subpath: '', relativePath: 'test.txt'),
      ];

      final result = await ZipArchiveService.exportFolderAsZip(
        folder: folder,
        items: items,
        downloadService: _MockDownloadService(),
      );

      expect(result, isNull);

      final tasks = TransferQueueService.instance.tasks
          .where((t) => t.id.startsWith('zip_folder_fail_start_1_'));
      expect(tasks.isNotEmpty, isTrue);
      expect(tasks.first.status, equals(TransferStatus.failed));
      expect(tasks.first.currentStage, equals('Initialization failed'));
    });

    test('Test 7: Safe deletion & resilient cleanup in deleteJobAndLocalFile',
        () async {
      // Sub-case A: Normal deletion of existing physical file and Hive job
      final tempTestFile =
          File('${tempHiveDir.path}/test_del_${DateTime.now().millisecondsSinceEpoch}.zip')
            ..writeAsStringSync('dummy zip content');

      final job = DownloadJob(
        fileId: 'job_to_delete_1',
        name: 'delete_me.zip',
        mimeType: 'application/zip',
        sizeMb: 1.0,
        status: 'completed',
        localPath: tempTestFile.path,
        addedAt: now,
        completedAt: now,
      );

      await downloadsBox.put(job.fileId, job);
      expect(downloadsBox.containsKey('job_to_delete_1'), isTrue);
      expect(tempTestFile.existsSync(), isTrue);

      await downloadQueueService.deleteJobAndLocalFile('job_to_delete_1');

      expect(tempTestFile.existsSync(), isFalse);
      expect(downloadsBox.containsKey('job_to_delete_1'), isFalse);

      // Sub-case B: File is already missing / file deletion fails — Hive entry MUST still be removed
      final missingJob = DownloadJob(
        fileId: 'job_missing_file_2',
        name: 'already_gone.zip',
        mimeType: 'application/zip',
        sizeMb: 1.0,
        status: 'completed',
        localPath: '/non/existent/path/never_created.zip',
        addedAt: now,
        completedAt: now,
      );

      await downloadsBox.put(missingJob.fileId, missingJob);
      expect(downloadsBox.containsKey('job_missing_file_2'), isTrue);

      await downloadQueueService.deleteJobAndLocalFile('job_missing_file_2');

      expect(downloadsBox.containsKey('job_missing_file_2'), isFalse,
          reason: 'Hive record must be cleanly removed even when local file is missing/fails');
    });
  });
}
