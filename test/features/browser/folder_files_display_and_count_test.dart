/*
 * File: folder_files_display_and_count_test.dart
 * Description: Reproduction tests reproducing folder file wipeout on sync, phantom item counts, and Hive folder count desync.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_partition.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/pending_action.dart';
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/sync_queue_service.dart';
import 'package:telstorage/core/services/sync_service.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:flutter/material.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_filter_helper.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/widgets/browser_grid_content.dart';
import 'package:telstorage/features/storage/data/repositories/storage_repository.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';
import 'package:telstorage/core/theme/app_theme.dart';

class _MockTelegram extends TelegramService {
  final Map<String, Uint8List> uploadedFiles = {};
  Uint8List? lastUploadedBytes;
  String? lastUploadedFileName;

  @override
  Future<Map<String, dynamic>> uploadBytesWithFileId(
    Uint8List bytes,
    String filename, {
    void Function(int sent, int total)? onSendProgress,
  }) async {
    uploadedFiles[filename] = bytes;
    lastUploadedBytes = bytes;
    lastUploadedFileName = filename;
    return {'message_id': 9999, 'file_id': 'meta_new_file_id'};
  }

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
  ]) async {
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'file_id': 'original_file_id',
      'name': 'test.txt',
      'size_mb': 1.0,
      'mime_type': 'text/plain',
      'uploaded_at': '2026-01-01T00:00:00.000Z',
      'chunks': [],
    })));
  }

  @override
  Future<void> deleteMessage(int messageId) async {}

  @override
  Future<void> deleteMessages(List<int> messageIds) async {}
}

class _MockMetadataService extends MetadataService {
  AppMetadata meta;
  _MockMetadataService(this.meta, TelegramService telegram) : super(telegram);

  @override
  Future<AppMetadata> fetch() async => meta;

  @override
  Future<FolderPartition?> fetchFolderPartition(String folderId) async => null;

  @override
  Future<void> update(AppMetadata newMeta) async {
    meta = newMeta;
  }
}

class _MockSyncQueueService extends SyncQueueService {
  _MockSyncQueueService(super.fileManager);

  @override
  Future<void> processQueue({bool force = false}) async {}
}

class _FakeStorageRepo implements StorageRepositoryContract {
  final List<FolderRecord> folders;
  final List<FileRecord> files;

  _FakeStorageRepo({required this.folders, required this.files});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  List<FolderRecord> getFolders(String? parentId) => folders;

  @override
  List<FileRecord> getFiles(String? folderId) =>
      files.where((f) => f.folderId == folderId).toList();

  @override
  int getFilesInFolderCount(String folderId) {
    return files.where((f) => f.folderId == folderId).length;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bug Reproduction Tests (RED)', () {
    late Directory tempDir;
    late Box<FileRecord> filesBox;
    late Box<FolderRecord> foldersBox;
    late Box<PendingAction> pendingBox;
    late Box<int> partitionSyncBox;
    late HiveService hiveService;
    late _MockTelegram mockTelegram;
    SyncQueueService? syncQueue;

    setUp(() async {
      tempDir = await Directory.systemTemp
          .createTemp('telstorage_bug_repro_test_');
      Hive.init(tempDir.path);

      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(FileRecordAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(FolderRecordAdapter());
      }
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(PendingActionAdapter());
      }

      filesBox = await Hive.openBox<FileRecord>(AppConstants.filesBox);
      foldersBox = await Hive.openBox<FolderRecord>(AppConstants.foldersBox);
      pendingBox =
          await Hive.openBox<PendingAction>(AppConstants.pendingActionsBox);
      partitionSyncBox =
          await Hive.openBox<int>(AppConstants.partitionSyncBox);

      await filesBox.clear();
      await foldersBox.clear();
      await pendingBox.clear();
      await partitionSyncBox.clear();

      hiveService = HiveService.instance;
      mockTelegram = _MockTelegram();
      Connectivity.mockConnectionStatus = true;
    });

    tearDown(() async {
      Connectivity.mockConnectionStatus = null;
      syncQueue?.dispose();
      syncQueue = null;
      await filesBox.close();
      await foldersBox.close();
      await pendingBox.close();
      await partitionSyncBox.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test(
        'REPRODUCTION 1: BrowserFilterHelper shows 0 items when folder is empty even if remote itemCount is positive',
        () {
      // Setup: Folder was previously thought to have 2 items in remote metadata,
      // but locally all files have been deleted or moved out (local count is 0).
      final emptyFolder = FolderRecord(
        id: 'folder_empty',
        name: 'EmptyFolder',
        createdAt: DateTime(2026, 1, 1),
        itemCount: 2, // Remote stale count
      );

      final repo = _FakeStorageRepo(
        folders: [emptyFolder],
        files: [], // No files in repository
      );

      final result = BrowserFilterHelper.loadAndFilterContents(
        repository: repo,
        folderId: null,
        category: null,
        searchQuery: '',
        sortOption: BrowserSortOption.name,
        sortAscending: true,
      );

      // In the buggy code, counts['folder_empty'] falls back to f.itemCount (2)
      // because `localCount > 0 ? localCount : f.itemCount` evaluates 0 > 0 as false!
      // The expected behavior is that the verified local count (0) is shown.
      expect(
        result.folderItemCounts['folder_empty'],
        0,
        reason:
            'Empty folder must show 0 items, not fallback to stale remote itemCount: 2',
      );
    });

    test(
        'REPRODUCTION 2: syncFolderPartition must NOT delete local files in folder when cloud partition has no message ID yet',
        () async {
      // Setup: A file uploaded 30 minutes ago was moved into 'folder_target'.
      // The cloud partition does not exist yet (cloudMessageId == null).
      final targetFolder = FolderRecord(
        id: 'folder_target',
        name: 'TargetFolder',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      await hiveService.saveFolder(targetFolder);

      final movedFile = FileRecord(
        fileId: 'file_in_target',
        name: 'document.pdf',
        metadataMessageId: 50,
        sizeMb: 3.5,
        mimeType: 'application/pdf',
        uploadedAt: DateTime.now().subtract(const Duration(minutes: 30)),
        folderId: 'folder_target',
        chunkCount: 1,
        sha256Hash: 'hash_abc',
      );
      await hiveService.saveFile(movedFile);

      final appMeta = AppMetadata(
        owner: 'test_owner',
        storageUsedMb: 3.5,
        totalFiles: 1,
        metadataMessageId: 10,
        lastSynced: DateTime.now(),
        categories: {},
        folders: [targetFolder.toFolder()],
        folderPartitionsMap: {}, // 'folder_target' has no cloudMessageId yet!
      );

      final metaService = _MockMetadataService(appMeta, mockTelegram);
      final syncService = SyncService(
        metaService,
        hiveService,
      );

      // Act: User opens 'folder_target', triggering syncFolderPartition
      await syncService.syncFolderPartition('folder_target', meta: appMeta);

      // In buggy code:
      // if (cloudMessageId == null) {
      //   _cleanStaleLocalFilesInFolder(targetFolderId, const {}, pendingSets);
      // }
      // This wipes out 'file_in_target' because it was uploaded 30 mins ago and not in empty set {}!
      final preservedFile = hiveService.getFile('file_in_target');
      expect(
        preservedFile,
        isNotNull,
        reason:
            'syncFolderPartition must not wipe local files when cloud partition is empty/uninitialized',
      );
    });

    test(
        'REPRODUCTION 3: StorageRepository.moveFile updates FolderRecord.itemCount in Hive for source and destination',
        () async {
      final srcFolder = FolderRecord(
        id: 'src_f',
        name: 'Source',
        createdAt: DateTime.now(),
        itemCount: 1,
      );
      final dstFolder = FolderRecord(
        id: 'dst_f',
        name: 'Destination',
        createdAt: DateTime.now(),
        itemCount: 0,
      );
      await hiveService.saveFolder(srcFolder);
      await hiveService.saveFolder(dstFolder);

      final file = FileRecord(
        fileId: 'movable_file',
        name: 'note.txt',
        metadataMessageId: 10,
        sizeMb: 0.1,
        mimeType: 'text/plain',
        uploadedAt: DateTime.now(),
        folderId: 'src_f',
        chunkCount: 1,
        sha256Hash: '',
      );
      await hiveService.saveFile(file);

      final meta = AppMetadata(
        owner: 'test_owner',
        storageUsedMb: 0.1,
        totalFiles: 1,
        metadataMessageId: 10,
        lastSynced: DateTime.now(),
        categories: {},
        folders: [srcFolder.toFolder(), dstFolder.toFolder()],
      );
      final metaService = _MockMetadataService(meta, mockTelegram);
      final fileManager = FileManagerService(
        metaService,
        mockTelegram,
        hiveService,
      );
      syncQueue = _MockSyncQueueService(fileManager);
      ServiceLocator.instance.setSyncQueueForTesting(syncQueue!);

      final repo = StorageRepository(hiveService, fileManager, metaService);

      await repo.moveFile('movable_file', 'dst_f');

      final updatedSrc = hiveService.getFolder('src_f');
      final updatedDst = hiveService.getFolder('dst_f');

      expect(updatedSrc?.itemCount, 0,
          reason: 'Source folder itemCount should decrement to 0');
      expect(updatedDst?.itemCount, 1,
          reason: 'Destination folder itemCount should increment to 1');
    });

    test(
        'REPRODUCTION 4: FileManager.copyFile serializes file_id (not id) in copied metadata',
        () async {
      final orig = FileRecord(
        fileId: 'original_file_id',
        name: 'test.txt',
        metadataMessageId: 200,
        metadataFileId: 'meta_orig',
        sizeMb: 1.0,
        mimeType: 'text/plain',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: '',
      );
      await hiveService.saveFile(orig);

      final meta = AppMetadata(
        owner: 'test_owner',
        storageUsedMb: 1.0,
        totalFiles: 1,
        metadataMessageId: 10,
        lastSynced: DateTime.now(),
        categories: {
          'documents': CategoryStat(count: 1, sizeMb: 1.0),
          'others': CategoryStat(count: 0, sizeMb: 0.0),
        },
        folders: [],
      );
      final metaService = _MockMetadataService(meta, mockTelegram);
      final fileManager = FileManagerService(
        metaService,
        mockTelegram,
        hiveService,
      );

      await fileManager.copyFile(
        originalFileId: 'original_file_id',
        newFileId: 'copied_file_id',
        newName: 'test_copy.txt',
        targetFolderId: null,
      );

      final copiedBytes = mockTelegram.uploadedFiles['copied_file_id.json'];
      expect(copiedBytes, isNotNull);
      final decodedJson = jsonDecode(
        utf8.decode(copiedBytes!),
      ) as Map<String, dynamic>;

      expect(
        decodedJson['file_id'],
        'copied_file_id',
        reason:
            "FileManager.copyFile must set 'file_id' to the newFileId in metadata JSON",
      );
    });

    testWidgets(
        'TEST 5: BrowserGridContent shows files section loading indicator when folders exist and files are loading',
        (tester) async {
      final state = BrowserState(
        currentFolderId: 'folder_with_sub',
        folders: [
          FolderRecord(
            id: 'sub_1',
            name: 'Subfolder',
            createdAt: DateTime.now(),
          ),
        ],
        files: [],
        isLoading: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: BrowserGridContent(
              state: state,
              onToggleSelection: (_, {required isFolder}) {},
              onOpenFolder: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('FOLDERS'), findsOneWidget);
      expect(find.text('FILES'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
