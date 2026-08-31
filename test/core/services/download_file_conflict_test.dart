/*
 * File: download_file_conflict_test.dart
 * Description: Unit and lifecycle tests for download conflict handling, atomic staging & overwrite, dynamic collision resolution, and transient queue policy tracking.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/download_job.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/download_queue_service.dart';
import 'package:telstorage/core/services/download_service.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/core/utils/native_save_helper.dart';

class _MockDownloadService implements DownloadService {
  @override
  Future<Uint8List> downloadFile(
    FileRecord record,
    Function(double progress, String status) onProgress,
  ) async {
    return Uint8List.fromList([1, 2, 3, 4]);
  }

  @override
  Future<SaveResult> saveAndOpen(
    Uint8List bytes,
    String filename, {
    String? mimeType,
    String? subpath,
    DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
  }) async {
    return SaveResult(
      success: true,
      savedPath: '/mock/path/$filename',
      message: 'OK',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<DownloadJob> downloadsBox;
  late DownloadQueueService queueService;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('telstorage_conflict_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FileRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(FolderRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(DownloadJobAdapter());
    }
    Connectivity.mockConnectionStatus = true;
  });

  setUp(() async {
    await Hive.openBox<FileRecord>(AppConstants.filesBox);
    await Hive.openBox<FolderRecord>(AppConstants.foldersBox);
    downloadsBox = await Hive.openBox<DownloadJob>(AppConstants.downloadsBox);
    await downloadsBox.clear();
    TransferQueueService.instance.clearAll();

    final downloadService = _MockDownloadService();
    queueService =
        DownloadQueueService(downloadService, AppConstants.downloadsBox);
    ServiceLocator.instance.setDownloadQueueForTesting(queueService);
    ServiceLocator.instance.setHiveForTesting(HiveService.instance);
    ServiceLocator.instance.setInitializedForTesting(true);
  });

  tearDown(() async {
    await downloadsBox.clear();
    await downloadsBox.close();
    await Hive.box<FileRecord>(AppConstants.filesBox).clear();
    await Hive.box<FileRecord>(AppConstants.filesBox).close();
    await Hive.box<FolderRecord>(AppConstants.foldersBox).clear();
    await Hive.box<FolderRecord>(AppConstants.foldersBox).close();
    ServiceLocator.instance.setInitializedForTesting(false);
  });

  tearDownAll(() async {
    Connectivity.mockConnectionStatus = null;
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Path and Filename Sanitization', () {
    test(
        'resolveSafeFilename strips forbidden characters and leading/trailing dots',
        () {
      expect(resolveSafeFilename('image:photo?.png'), 'image_photo.png');
      expect(resolveSafeFilename('../secret.txt'), 'secret.txt');
      expect(resolveSafeFilename('...my_file.pdf...'), 'my_file.pdf');
      expect(resolveSafeFilename(''), 'unnamed_file');
    });

    test('resolveSafeSubpath sanitizes folder paths and prevents traversal',
        () {
      expect(resolveSafeSubpath('../../documents', 'test.pdf'), 'documents');
      expect(resolveSafeSubpath(null, 'photo.jpg'), 'photo');
      expect(resolveSafeSubpath('', 'song.mp3'), 'audio');
    });
  });

  group('Atomic Overwrite & Collision Resolution (NativeSaveHelper)', () {
    test(
        'resolveNonCollidingFilename auto-increments when destination file exists',
        () async {
      final targetDir = await resolveTargetDirectory(subpath: 'test_category');
      final file1 = File(p.join(targetDir.path, 'sample.txt'));
      await file1.writeAsString('initial');

      final nonColliding = await resolveNonCollidingFilename('sample.txt',
          subpath: 'test_category');
      expect(nonColliding, 'sample (1).txt');

      final file2 = File(p.join(targetDir.path, 'sample (1).txt'));
      await file2.writeAsString('second');

      final nonColliding2 = await resolveNonCollidingFilename('sample.txt',
          subpath: 'test_category');
      expect(nonColliding2, 'sample (2).txt');

      // Cleanup
      if (file1.existsSync()) await file1.delete();
      if (file2.existsSync()) await file2.delete();
    });

    test(
        'saveNative with overwrite atomically replaces file bytes with no temp artifacts left',
        () async {
      final initialBytes = Uint8List.fromList([1, 1, 1]);
      final newBytes = Uint8List.fromList([2, 2, 2, 2]);

      // 1. Initial write
      final res1 = await saveNative(initialBytes, 'atomic_test.bin',
          subpath: 'test_cat');
      expect(res1.success, isTrue);
      final filePath = res1.savedPath!;
      expect(File(filePath).readAsBytesSync(), initialBytes);

      // 2. Atomic overwrite
      final res2 = await saveNative(
        newBytes,
        'atomic_test.bin',
        subpath: 'test_cat',
        policy: DownloadConflictPolicy.overwrite,
      );
      expect(res2.success, isTrue);
      expect(File(filePath).readAsBytesSync(), newBytes);

      // Verify no temporary files remain in folder
      final dir = File(filePath).parent;
      final tempFiles = dir.listSync().where((e) =>
          p.basename(e.path).startsWith('.') &&
          p.basename(e.path).contains('.tmp_'));
      expect(tempFiles, isEmpty);

      // Cleanup
      if (File(filePath).existsSync()) await File(filePath).delete();
    });

    test(
        'saveNative with keepBoth creates numbered copy leaving original intact',
        () async {
      final initialBytes = Uint8List.fromList([10, 20]);
      final secondBytes = Uint8List.fromList([30, 40]);

      final res1 =
          await saveNative(initialBytes, 'keep_both.txt', subpath: 'test_cat');
      expect(res1.success, isTrue);

      final res2 = await saveNative(
        secondBytes,
        'keep_both.txt',
        subpath: 'test_cat',
        policy: DownloadConflictPolicy.keepBoth,
      );
      expect(res2.success, isTrue);
      expect(res2.savedPath, contains('keep_both (1).txt'));

      // Both files exist with distinct bytes
      expect(File(res1.savedPath!).readAsBytesSync(), initialBytes);
      expect(File(res2.savedPath!).readAsBytesSync(), secondBytes);

      // Cleanup
      if (File(res1.savedPath!).existsSync()) {
        await File(res1.savedPath!).delete();
      }
      if (File(res2.savedPath!).existsSync()) {
        await File(res2.savedPath!).delete();
      }
    });

    test(
        'saveNative with skip returns success with existing path without overwriting',
        () async {
      final initialBytes = Uint8List.fromList([100]);
      final skipBytes = Uint8List.fromList([200]);

      final res1 =
          await saveNative(initialBytes, 'skip_me.txt', subpath: 'test_cat');
      expect(res1.success, isTrue);

      final res2 = await saveNative(
        skipBytes,
        'skip_me.txt',
        subpath: 'test_cat',
        policy: DownloadConflictPolicy.skip,
      );
      expect(res2.success, isTrue);
      expect(res2.savedPath, equals(res1.savedPath));
      // Original bytes preserved
      expect(File(res1.savedPath!).readAsBytesSync(), initialBytes);

      // Cleanup
      if (File(res1.savedPath!).existsSync()) {
        await File(res1.savedPath!).delete();
      }
    });

    test('cleanStaleTempFiles sweeps orphaned .tmp_ staging files', () async {
      final targetDir = await resolveTargetDirectory(subpath: 'test_sweep');
      final orphan = File(p.join(targetDir.path, '.orphan.bin.tmp_12345_abcd'));
      await orphan.writeAsString('garbage');
      expect(orphan.existsSync(), isTrue);

      await cleanStaleTempFiles(subpath: 'test_sweep');
      expect(orphan.existsSync(), isFalse);
    });
  });

  group('DownloadQueueService Conflict & Policy Tracking', () {
    test('checkFileConflict detects completed Hive jobs and on-disk files',
        () async {
      final file = FileRecord(
        fileId: 'conflict_f1',
        name: 'report.pdf',
        mimeType: 'application/pdf',
        sizeMb: 2.0,
        uploadedAt: DateTime.now(),
        metadataMessageId: 101,
        chunkCount: 1,
        sha256Hash: 'hash1',
      );

      // Initially no conflict
      expect(await queueService.checkFileConflict(file), isFalse);

      // Add completed Hive job
      await downloadsBox.put(
        file.fileId,
        DownloadJob(
          fileId: file.fileId,
          name: file.name,
          mimeType: file.mimeType,
          sizeMb: file.sizeMb,
          status: 'completed',
          progress: 1.0,
          addedAt: DateTime.now(),
        ),
      );

      expect(await queueService.checkFileConflict(file), isTrue);
    });

    test(
        'enqueueDownload registers transient policy in _inFlightPolicies and resets active tokens',
        () async {
      final file = FileRecord(
        fileId: 'policy_f2',
        name: 'video.mp4',
        mimeType: 'video/mp4',
        sizeMb: 15.0,
        uploadedAt: DateTime.now(),
        metadataMessageId: 102,
        chunkCount: 1,
        sha256Hash: 'hash2',
      );
      await HiveService.instance.saveFile(file);

      await queueService.enqueueDownload(
        file,
        policy: DownloadConflictPolicy.keepBoth,
      );

      expect(queueService.getConflictPolicy(file.fileId),
          DownloadConflictPolicy.keepBoth);
      expect(queueService.isCancelled(file.fileId), isFalse);
      expect(queueService.isPaused(file.fileId), isFalse);

      await Future.delayed(const Duration(milliseconds: 150));
    });
  });
}
