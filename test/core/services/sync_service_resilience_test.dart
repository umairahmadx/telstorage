/*
 * File: sync_service_resilience_test.dart
 * Description: Unit tests validating SyncService anti-reversion resilience under pending deletions, moves, and renames.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_partition.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/pending_action.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/sync_service.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/utils/connectivity.dart';

class FakeTelegramService extends TelegramService {}

class FakeMetadataService extends MetadataService {
  AppMetadata mockMeta;
  Map<String, FolderPartition> partitions;

  FakeMetadataService({
    required this.mockMeta,
    required this.partitions,
  }) : super(FakeTelegramService());

  @override
  Future<AppMetadata> fetch() async => mockMeta;

  @override
  Future<FolderPartition?> fetchFolderPartition(String folderId) async {
    return partitions[folderId];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HiveService hiveService;
  late Box<FileRecord> filesBox;
  late Box<FolderRecord> foldersBox;
  late Box<PendingAction> pendingBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('telstorage_sync_test_');
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

    await filesBox.clear();
    await foldersBox.clear();
    await pendingBox.clear();

    hiveService = HiveService.instance;
    Connectivity.mockConnectionStatus = true;
  });

  tearDown(() async {
    Connectivity.mockConnectionStatus = null;
    await filesBox.close();
    await foldersBox.close();
    await pendingBox.close();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SyncService Anti-Reversion & State Resilience Tests', () {
    test(
        'TC-01: syncFromTelegram does NOT restore deleted files when actionDeleteFile is pending in queue',
        () async {
      // Remote Telegram still has 'file_001' in 'root' partition
      final remoteRef = FileRef(
        fileId: 'file_001',
        metaFileId: 'meta_001',
        name: 'vacation.jpg',
        sizeMb: 5.0,
      );

      final fakeMeta = AppMetadata(
        owner: 'test@user.com',
        storageUsedMb: 5.0,
        totalFiles: 1,
        metadataMessageId: 100,
        folders: [],
        categories: {'images': CategoryStat(count: 1, sizeMb: 5.0)},
        folderPartitionsMap: {'root': 200},
        lastSynced: DateTime.now(),
      );

      final fakePartition = FolderPartition(
        folderId: 'root',
        messageId: 200,
        files: [remoteRef],
      );

      final metadataService = FakeMetadataService(
        mockMeta: fakeMeta,
        partitions: {'root': fakePartition},
      );

      // Local state: File was deleted locally and pending in queue
      await pendingBox.put(
        'pending_del_1',
        PendingAction(
          id: 'pending_del_1',
          actionType: AppConstants.actionDeleteFile,
          payload: {'fileId': 'file_001', 'folderId': null},
          timestamp: DateTime.now(),
        ),
      );

      final syncService = SyncService(metadataService, hiveService);
      final result = await syncService.syncFromTelegram();

      // Verify file was skipped and not re-added into Hive
      expect(result.added, 0);
      expect(hiveService.getFile('file_001'), isNull);
    });

    test(
        'TC-02: syncFromTelegram does NOT restore deleted folders when actionDeleteFolder is pending in queue',
        () async {
      final remoteFolder = Folder(
        id: 'folder_vacation',
        name: 'Vacation Photos',
        createdAt: DateTime.now(),
      );

      final fakeMeta = AppMetadata(
        owner: 'test@user.com',
        storageUsedMb: 0.0,
        totalFiles: 0,
        metadataMessageId: 100,
        folders: [remoteFolder],
        categories: {},
        folderPartitionsMap: {},
        lastSynced: DateTime.now(),
      );

      final metadataService = FakeMetadataService(
        mockMeta: fakeMeta,
        partitions: {},
      );

      // Local state: Folder was deleted locally and pending in queue
      await pendingBox.put(
        'pending_del_folder_1',
        PendingAction(
          id: 'pending_del_folder_1',
          actionType: AppConstants.actionDeleteFolder,
          payload: {'folderId': 'folder_vacation'},
          timestamp: DateTime.now(),
        ),
      );

      final syncService = SyncService(metadataService, hiveService);
      final result = await syncService.syncFromTelegram();

      // Verify folder was skipped and not re-added into Hive
      expect(result.added, 0);
      expect(hiveService.getFolder('folder_vacation'), isNull);
    });

    test(
        'TC-03: syncFromTelegram preserves local optimistic file rename when remote partition has old name',
        () async {
      // Remote Telegram has 'document_old.pdf'
      final remoteRef = FileRef(
        fileId: 'file_002',
        metaFileId: 'meta_002',
        name: 'document_old.pdf',
        sizeMb: 2.0,
      );

      final fakeMeta = AppMetadata(
        owner: 'test@user.com',
        storageUsedMb: 2.0,
        totalFiles: 1,
        metadataMessageId: 100,
        folders: [],
        categories: {},
        folderPartitionsMap: {'root': 200},
        lastSynced: DateTime.now(),
      );

      final fakePartition = FolderPartition(
        folderId: 'root',
        messageId: 200,
        files: [remoteRef],
      );

      final metadataService = FakeMetadataService(
        mockMeta: fakeMeta,
        partitions: {'root': fakePartition},
      );

      // Local state: File was renamed to 'document_NEW.pdf'
      final localFile = FileRecord(
        fileId: 'file_002',
        name: 'document_NEW.pdf',
        metadataMessageId: 10,
        metadataFileId: 'meta_002',
        sizeMb: 2.0,
        mimeType: 'application/pdf',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'hash',
      );
      await hiveService.saveFile(localFile);

      // Pending action recorded in queue
      await pendingBox.put(
        'pending_rename_1',
        PendingAction(
          id: 'pending_rename_1',
          actionType: AppConstants.actionRenameFile,
          payload: {'fileId': 'file_002', 'name': 'document_NEW.pdf'},
          timestamp: DateTime.now(),
        ),
      );

      final syncService = SyncService(metadataService, hiveService);
      await syncService.syncFromTelegram();

      // Verify local optimistic rename was preserved and NOT overwritten by 'document_old.pdf'
      final fileInHive = hiveService.getFile('file_002');
      expect(fileInHive, isNotNull);
      expect(fileInHive!.name, 'document_NEW.pdf');
    });

    test(
        'TC-04: syncFromTelegram preserves local optimistic file move when remote partition has old folderId',
        () async {
      // Remote Telegram has file in 'root' (null folderId)
      final remoteRef = FileRef(
        fileId: 'file_003',
        metaFileId: 'meta_003',
        name: 'budget.xlsx',
        folderId: null,
        sizeMb: 1.5,
      );

      final fakeMeta = AppMetadata(
        owner: 'test@user.com',
        storageUsedMb: 1.5,
        totalFiles: 1,
        metadataMessageId: 100,
        folders: [],
        categories: {},
        folderPartitionsMap: {'root': 200},
        lastSynced: DateTime.now(),
      );

      final fakePartition = FolderPartition(
        folderId: 'root',
        messageId: 200,
        files: [remoteRef],
      );

      final metadataService = FakeMetadataService(
        mockMeta: fakeMeta,
        partitions: {'root': fakePartition},
      );

      // Local state: File was moved to 'folder_finance'
      final localFile = FileRecord(
        fileId: 'file_003',
        name: 'budget.xlsx',
        folderId: 'folder_finance',
        metadataMessageId: 10,
        metadataFileId: 'meta_003',
        sizeMb: 1.5,
        mimeType: 'application/vnd.ms-excel',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'hash',
      );
      await hiveService.saveFile(localFile);

      // Pending action recorded in queue
      await pendingBox.put(
        'pending_move_1',
        PendingAction(
          id: 'pending_move_1',
          actionType: AppConstants.actionMoveFile,
          payload: {'fileId': 'file_003', 'folderId': 'folder_finance'},
          timestamp: DateTime.now(),
        ),
      );

      final syncService = SyncService(metadataService, hiveService);
      await syncService.syncFromTelegram();

      // Verify local optimistic folderId was preserved and NOT reset to null
      final fileInHive = hiveService.getFile('file_003');
      expect(fileInHive, isNotNull);
      expect(fileInHive!.folderId, 'folder_finance');
    });
  });
}
