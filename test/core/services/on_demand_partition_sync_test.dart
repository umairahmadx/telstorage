/*
 * File: on_demand_partition_sync_test.dart
 * Description: Comprehensive unit tests validating on-demand folder partitioning, bootstrap seeding of recent files and root partition, ETag caching, offline states, and uncached folder deletion.
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
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/sync_service.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:telstorage/core/utils/connectivity.dart';

class MockTelegramService extends TelegramService {
  final List<int> deletedMessageIds = [];

  @override
  Future<void> deleteMessage(int messageId) async {
    deletedMessageIds.add(messageId);
  }

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
  ]) async {
    return Uint8List.fromList(utf8.encode(jsonEncode({'chunks': []})));
  }
}

class MockMetadataService extends MetadataService {
  AppMetadata mockMeta;
  Map<String, FolderPartition> partitions;
  int fetchPartitionCallCount = 0;

  MockMetadataService({
    required this.mockMeta,
    required this.partitions,
    required TelegramService telegram,
  }) : super(telegram);

  @override
  Future<AppMetadata> fetch() async => mockMeta;

  @override
  Future<FolderPartition?> fetchFolderPartition(String folderId) async {
    fetchPartitionCallCount++;
    return partitions[folderId];
  }

  @override
  Future<void> update(AppMetadata meta) async {
    mockMeta = meta;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HiveService hiveService;
  late Box<FileRecord> filesBox;
  late Box<FolderRecord> foldersBox;
  late Box<PendingAction> pendingBox;
  late Box<int> partitionSyncBox;
  late MockTelegramService mockTelegram;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('telstorage_partition_test_');
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
    partitionSyncBox = await Hive.openBox<int>(AppConstants.partitionSyncBox);

    await filesBox.clear();
    await foldersBox.clear();
    await pendingBox.clear();
    await partitionSyncBox.clear();

    hiveService = HiveService.instance;
    mockTelegram = MockTelegramService();
    Connectivity.mockConnectionStatus = true;
  });

  tearDown(() async {
    Connectivity.mockConnectionStatus = null;
    await filesBox.close();
    await foldersBox.close();
    await pendingBox.close();
    await partitionSyncBox.close();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('On-Demand Partitioning & Bootstrap Tests', () {
    test('TC-01: Bootstrap sync immediately seeds recent files and root partition, leaving subfolders unpartitioned',
        () async {
      final recentRef = FileRef(
        fileId: 'recent_001',
        metaFileId: 'meta_recent',
        name: 'presentation.pdf',
        sizeMb: 12.5,
        uploadedAt: DateTime.now().toIso8601String(),
      );

      final rootRef = FileRef(
        fileId: 'root_001',
        metaFileId: 'meta_root',
        name: 'readme.txt',
        sizeMb: 0.1,
        uploadedAt: DateTime.now().toIso8601String(),
      );

      final subfolderRef = FileRef(
        fileId: 'sub_001',
        metaFileId: 'meta_sub',
        name: 'photo.jpg',
        sizeMb: 3.5,
        folderId: 'folder_sub',
        uploadedAt: DateTime.now().toIso8601String(),
      );

      final mockMeta = AppMetadata(
        owner: 'test@user.com',
        storageUsedMb: 16.1,
        totalFiles: 3,
        metadataMessageId: 100,
        folders: [
          Folder(id: 'folder_sub', name: 'Vacation', createdAt: DateTime.now()),
        ],
        folderPartitionsMap: {
          AppConstants.rootFolderPartitionId: 201,
          'folder_sub': 202,
        },
        recentFiles: [recentRef],
        categories: {},
        lastSynced: DateTime.now(),
      );

      final mockMetadataService = MockMetadataService(
        mockMeta: mockMeta,
        partitions: {
          AppConstants.rootFolderPartitionId: FolderPartition(
            folderId: AppConstants.rootFolderPartitionId,
            messageId: 201,
            files: [rootRef],
          ),
          'folder_sub': FolderPartition(
            folderId: 'folder_sub',
            messageId: 202,
            files: [subfolderRef],
          ),
        },
        telegram: mockTelegram,
      );

      final syncService = SyncService(mockMetadataService, hiveService);

      // Execute bootstrap sync
      final result = await syncService.syncFromTelegram();
      expect(result.added, 1);

      // Verify folders were added
      expect(hiveService.allFolders.length, 1);
      expect(hiveService.allFolders.first.id, 'folder_sub');

      // Verify recent file is seeded into local Hive
      final cachedRecent = hiveService.getFile('recent_001');
      expect(cachedRecent, isNotNull);
      expect(cachedRecent!.name, 'presentation.pdf');

      // Verify root partition file is seeded into local Hive
      final cachedRoot = hiveService.getFile('root_001');
      expect(cachedRoot, isNotNull);
      expect(cachedRoot!.name, 'readme.txt');

      // Verify root partition ETag message ID is recorded
      expect(
          hiveService.getFolderPartitionMessageId(AppConstants.rootFolderPartitionId),
          201);

      // Verify subfolder partition was NOT fetched during bootstrap
      expect(hiveService.getFile('sub_001'), isNull);
      expect(hiveService.getFolderPartitionMessageId('folder_sub'), isNull);
      expect(mockMetadataService.fetchPartitionCallCount, 1); // Only root was fetched!
    });

    test('TC-02: On-demand sync fetches subfolder partition and subsequent call uses ETag cache hit',
        () async {
      final subfolderRef = FileRef(
        fileId: 'sub_001',
        metaFileId: 'meta_sub',
        name: 'photo.jpg',
        sizeMb: 3.5,
        folderId: 'folder_sub',
        uploadedAt: DateTime.now().toIso8601String(),
      );

      final mockMeta = AppMetadata(
        owner: 'test@user.com',
        storageUsedMb: 3.5,
        totalFiles: 1,
        metadataMessageId: 100,
        folders: [
          Folder(id: 'folder_sub', name: 'Vacation', createdAt: DateTime.now()),
        ],
        folderPartitionsMap: {
          'folder_sub': 301,
        },
        recentFiles: [],
        categories: {},
        lastSynced: DateTime.now(),
      );

      final mockMetadataService = MockMetadataService(
        mockMeta: mockMeta,
        partitions: {
          'folder_sub': FolderPartition(
            folderId: 'folder_sub',
            messageId: 301,
            files: [subfolderRef],
          ),
        },
        telegram: mockTelegram,
      );

      final syncService = SyncService(mockMetadataService, hiveService);

      // Subfolder is not yet cached
      expect(hiveService.getFolderPartitionMessageId('folder_sub'), isNull);

      // First fetch: on-demand network call
      final didUpdate = await syncService.syncFolderPartition('folder_sub', meta: mockMeta);
      expect(didUpdate, isTrue);
      expect(mockMetadataService.fetchPartitionCallCount, 1);
      expect(hiveService.getFolderPartitionMessageId('folder_sub'), 301);
      expect(hiveService.getFile('sub_001'), isNotNull);

      // Second fetch: ETag matches 301 -> returns false immediately without network call
      final didUpdateSecond =
          await syncService.syncFolderPartition('folder_sub', meta: mockMeta);
      expect(didUpdateSecond, isFalse);
      expect(mockMetadataService.fetchPartitionCallCount, 1); // No new network call!
    });

    test('TC-03: Deleting an uncached folder cleans remote partition, file messages, and stats without orphans',
        () async {
      final remoteRef = FileRef(
        fileId: 'unindexed_file',
        metaFileId: 'unindexed_meta',
        name: 'archive.tar',
        sizeMb: 50.0,
        mimeType: 'application/x-tar',
        folderId: 'folder_uncached',
        metadataMessageId: 444,
        uploadedAt: DateTime.now().toIso8601String(),
      );

      final mockMeta = AppMetadata(
        owner: 'test@user.com',
        storageUsedMb: 50.0,
        totalFiles: 1,
        metadataMessageId: 100,
        folders: [
          Folder(id: 'folder_uncached', name: 'Old Archives', createdAt: DateTime.now()),
        ],
        folderPartitionsMap: {
          'folder_uncached': 999, // Remote partition message ID
        },
        recentFiles: [],
        categories: {
          'archives': CategoryStat(count: 1, sizeMb: 50.0),
        },
        lastSynced: DateTime.now(),
      );

      final mockMetadataService = MockMetadataService(
        mockMeta: mockMeta,
        partitions: {
          'folder_uncached': FolderPartition(
            folderId: 'folder_uncached',
            messageId: 999,
            files: [remoteRef],
          ),
        },
        telegram: mockTelegram,
      );

      final fileManager = FileManagerService(
        mockMetadataService,
        mockTelegram,
        hiveService,
      );

      // User deletes folder_uncached. Note: fileSnapshots is empty because local Hive never cached it!
      await fileManager.deleteFolder(
        'folder_uncached',
        folderIds: ['folder_uncached'],
        fileSnapshots: [],
      );

      // Verify remote partition message and remote file metadata message were deleted on Telegram
      expect(mockTelegram.deletedMessageIds, contains(444)); // remote file message
      expect(mockTelegram.deletedMessageIds, contains(999)); // remote partition message

      // Verify partition is removed from metadata
      expect(mockMeta.folderPartitionsMap.containsKey('folder_uncached'), isFalse);
      expect(mockMeta.folders.any((f) => f.id == 'folder_uncached'), isFalse);
      expect(mockMeta.totalFiles, 0);
      expect(mockMeta.storageUsedMb, 0.0);
      expect(mockMeta.categories['archives']?.count, 0);
      expect(mockMeta.categories['archives']?.sizeMb, 0.0);
    });

    test('TC-04: ensureFolderTreeSynced throws OfflineException if an uncached folder is tapped offline',
        () async {
      final mockMeta = AppMetadata(
        owner: 'test@user.com',
        storageUsedMb: 10.0,
        totalFiles: 1,
        metadataMessageId: 100,
        folders: [
          Folder(id: 'folder_offline', name: 'Offline Folder', createdAt: DateTime.now()),
        ],
        folderPartitionsMap: {
          'folder_offline': 555,
        },
        recentFiles: [],
        categories: {},
        lastSynced: DateTime.now(),
      );

      final mockMetadataService = MockMetadataService(
        mockMeta: mockMeta,
        partitions: {},
        telegram: mockTelegram,
      );

      final syncService = SyncService(mockMetadataService, hiveService);

      // Save folder in Hive (discovered from metadata)
      await hiveService.saveFolder(
        FolderRecord(id: 'folder_offline', name: 'Offline Folder', createdAt: DateTime.now()),
      );

      // Simulate offline mode
      Connectivity.mockConnectionStatus = false;

      // Expect OfflineException
      expect(
        () => syncService.ensureFolderTreeSynced('folder_offline'),
        throwsA(isA<OfflineException>()),
      );
    });
  });
}
