/*
 * File: upload_folder_helper_test.dart
 * Description: Unit tests validating local directory scanning, hierarchy creation, and isTemporaryCacheFile=false data-loss protection.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/download_conflict_policy.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/folder_stats.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_folder_helper.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_view_model.dart';

class FakeStorageRepository implements StorageRepositoryContract {
  final Map<String, FolderRecord> folders = {};
  int folderIdCounter = 1;

  @override
  Future<Result<String>> createFolder(String name, {String? parentId}) async {
    final id = 'folder_${folderIdCounter++}';
    final record = FolderRecord(
      id: id,
      name: name,
      parentId: parentId,
      createdAt: DateTime.now(),
    );
    folders[id] = record;
    return Success(id);
  }

  @override
  List<FolderRecord> getFolders(String? parentId) {
    return folders.values.where((f) => f.parentId == parentId).toList();
  }

  @override
  List<FileRecord> get currentFiles => [];
  @override
  List<FolderRecord> get currentFolders => folders.values.toList();
  @override
  FileRecord? getFile(String fileId) => null;
  @override
  FolderRecord? getFolder(String folderId) => folders[folderId];
  @override
  List<FileRecord> getFiles(String? folderId) => [];
  @override
  @override
  int getFilesInFolderCount(String folderId) => 0;
  @override
  FolderStats getFolderStats(String folderId) =>
      const FolderStats(fileCount: 0, subfolderCount: 0, totalSizeMb: 0);
  @override
  Future<Result<void>> copyFile(String fileId, String? targetFolderId) async =>
      const Success(null);
  @override
  Future<void> copyFolder(String folderId, String? targetParentId) async {}
  @override
  Future<Result<void>> deleteFile(String fileId) async => const Success(null);
  @override
  Future<Result<void>> deleteFolder(String folderId) async =>
      const Success(null);
  @override
  Future<Result<void>> enqueueDownload(FileRecord file,
          {String? subpath, DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite}) async =>
      const Success(null);
  @override
  Future<Result<void>> enqueueWebShare(FileRecord file,
          {String? password, int? expiryDays, String? vanitySlug}) async =>
      const Success(null);
  @override
  Future<void> moveFile(String fileId, String? newFolderId) async {}
  @override
  Future<void> moveFolder(String folderId, String? newParentId) async {}
  @override
  Future<Result<void>> renameFile(String fileId, String newName) async =>
      const Success(null);
  @override
  Future<Result<void>> renameFolder(String folderId, String newName) async =>
      const Success(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempTestDir;
  late FakeStorageRepository repository;
  late UploadBloc uploadBloc;

  setUp(() async {
    tempTestDir = Directory.systemTemp.createTempSync('upload_helper_test_');
    repository = FakeStorageRepository();
    uploadBloc = UploadBloc();
  });

  tearDown(() async {
    if (tempTestDir.existsSync()) {
      try {
        tempTestDir.deleteSync(recursive: true);
      } catch (_) {}
    }
    await uploadBloc.close();
  });

  group('UploadFolderHelper Local Scanning & Hierarchy Tests', () {
    test(
        'TC-01: Scans nested local directories and creates matching FolderRecords in TelStorage',
        () async {
      // Setup local folder tree:
      // tempTestDir/
      //   ├── file_root.txt
      //   ├── sub_a/
      //   │   └── file_a.txt
      //   └── sub_b/
      //       └── sub_nested/
      //           └── file_nested.txt
      File('${tempTestDir.path}/file_root.txt')
          .writeAsStringSync('Hello Root');
      final subA = Directory('${tempTestDir.path}/sub_a')..createSync();
      File('${subA.path}/file_a.txt').writeAsStringSync('Hello A');
      final subB = Directory('${tempTestDir.path}/sub_b')..createSync();
      final subNested = Directory('${subB.path}/sub_nested')..createSync();
      File('${subNested.path}/file_nested.txt')
          .writeAsStringSync('Hello Nested');

      final result = await UploadFolderHelper.scanAndQueueFolder(
        dirPath: tempTestDir.path,
        targetParentFolderId: 'parent_123',
        storageRepository: repository,
        uploadBloc: uploadBloc,
      );

      expect(result.filesCount, equals(3));
      // Root folder + sub_a + sub_b + sub_nested = 4 folders
      expect(result.foldersCount, equals(4));
      expect(result.queuedTasks.length, equals(3));

      // Verify root folder was created under targetParentFolderId
      final rootFolders = repository.getFolders('parent_123');
      expect(rootFolders.length, equals(1));
      final rootFolder = rootFolders.first;

      // Verify subfolders
      final rootSubfolders = repository.getFolders(rootFolder.id);
      expect(rootSubfolders.length, equals(2));
      expect(rootSubfolders.map((f) => f.name), containsAll(['sub_a', 'sub_b']));

      final subBFolder =
          rootSubfolders.firstWhere((f) => f.name == 'sub_b');
      final nestedFolders = repository.getFolders(subBFolder.id);
      expect(nestedFolders.length, equals(1));
      expect(nestedFolders.first.name, equals('sub_nested'));
    });

    test(
        'TC-02: Critical: Sets isTemporaryCacheFile=false on all folder-sourced tasks',
        () async {
      final file = File('${tempTestDir.path}/important_doc.pdf')
        ..writeAsStringSync('Important Document');

      final result = await UploadFolderHelper.scanAndQueueFolder(
        dirPath: tempTestDir.path,
        targetParentFolderId: null,
        storageRepository: repository,
        uploadBloc: uploadBloc,
      );

      expect(result.queuedTasks.length, equals(1));
      final task = result.queuedTasks.first;

      // Assert data loss protection
      expect(task.isTemporaryCacheFile, isFalse);
      expect(p.normalize(task.path!), equals(p.normalize(file.path)));
      expect(task.name, equals('important_doc.pdf'));
    });

    test(
        'TC-03: Critical: cleanupCacheFile() NEVER deletes the user original file on disk',
        () async {
      final originalFile = File('${tempTestDir.path}/user_photo.jpg')
        ..writeAsStringSync('Original photo bytes');

      expect(originalFile.existsSync(), isTrue);

      final result = await UploadFolderHelper.scanAndQueueFolder(
        dirPath: tempTestDir.path,
        targetParentFolderId: null,
        storageRepository: repository,
        uploadBloc: uploadBloc,
      );

      final task = result.queuedTasks.first;
      expect(task.isTemporaryCacheFile, isFalse);

      // Execute cleanupCacheFile (simulate post-upload task completion)
      await task.cleanupCacheFile();

      // Assert user's file is intact!
      expect(originalFile.existsSync(), isTrue);
      expect(originalFile.readAsStringSync(), equals('Original photo bytes'));
    });

    test(
        'TC-04: Throws FolderInaccessibleException when path does not exist',
        () async {
      expect(
        () => UploadFolderHelper.scanAndQueueFolder(
          dirPath: '${tempTestDir.path}/non_existent_dir_12345',
          targetParentFolderId: null,
          storageRepository: repository,
          uploadBloc: uploadBloc,
        ),
        throwsA(isA<FolderInaccessibleException>()),
      );
    });

    test(
        'TC-05: Returns 0 files and creates 1 folder for an empty directory',
        () async {
      final emptyDir = Directory('${tempTestDir.path}/empty_dir')..createSync();

      final result = await UploadFolderHelper.scanAndQueueFolder(
        dirPath: emptyDir.path,
        targetParentFolderId: null,
        storageRepository: repository,
        uploadBloc: uploadBloc,
      );

      expect(result.filesCount, equals(0));
      expect(result.foldersCount, equals(1));
      expect(result.queuedTasks, isEmpty);
    });

    test(
        'TC-06: Resilient scanning discovers files across multiple directory levels with various file types',
        () async {
      final mediaDir = Directory('${tempTestDir.path}/media')..createSync();
      final photosDir = Directory('${mediaDir.path}/photos')..createSync();
      final docsDir = Directory('${mediaDir.path}/docs')..createSync();

      File('${photosDir.path}/photo1.jpg').writeAsBytesSync([1, 2, 3, 4]);
      File('${photosDir.path}/photo2.png').writeAsBytesSync([5, 6, 7, 8]);
      File('${docsDir.path}/notes.txt').writeAsStringSync('Notes');
      File('${mediaDir.path}/summary.pdf').writeAsStringSync('PDF Summary');

      final result = await UploadFolderHelper.scanAndQueueFolder(
        dirPath: mediaDir.path,
        targetParentFolderId: null,
        storageRepository: repository,
        uploadBloc: uploadBloc,
      );

      expect(result.filesCount, equals(4));
      // Root (media) + photos + docs = 3 folders
      expect(result.foldersCount, equals(3));
      expect(result.queuedTasks.length, equals(4));

      final names = result.queuedTasks.map((t) => t.name).toList();
      expect(names, containsAll(['photo1.jpg', 'photo2.png', 'notes.txt', 'summary.pdf']));
    });
  });
}
