/*
 * File: file_move_partition_sync_test.dart
 * Description: Unit tests validating file move partition mechanics, oldFolderId preservation, and preventing fresh-install root partition reversion.
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
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/sync_queue_service.dart';
import 'package:telstorage/core/services/sync_service.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/features/storage/data/repositories/storage_repository.dart';

class TestMockTelegramService extends TelegramService {
  final Map<int, Uint8List> messageBytes = {};
  final List<int> deletedMessageIds = [];
  int _nextMessageId = 500;

  @override
  Future<Map<String, dynamic>> uploadBytesWithFileId(
    Uint8List bytes,
    String filename, {
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final msgId = _nextMessageId++;
    messageBytes[msgId] = bytes;
    return {
      'message_id': msgId,
      'file_id': 'meta_file_$msgId',
    };
  }

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

  @override
  Future<void> pinMessage(int messageId) async {}

  @override
  Future<int> getPinnedMessageId() async => 100;

  @override
  Future<String> getFileIdOfMessage(int messageId) async => 'pinned_meta';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HiveService hiveService;
  late Box<FileRecord> filesBox;
  late Box<FolderRecord> foldersBox;
  late Box<PendingAction> pendingBox;
  late Box<int> partitionSyncBox;
  late TestMockTelegramService mockTelegram;
  SyncQueueService? syncQueue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('file_move_test_');
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
    mockTelegram = TestMockTelegramService();
    Connectivity.mockConnectionStatus = true;
    TelegramRateLimiter.instance.reset();
  });

  tearDown(() async {
    Connectivity.mockConnectionStatus = null;
    syncQueue?.dispose();
    syncQueue = null;
    await filesBox.close();
    await foldersBox.close();
    await pendingBox.close();
    await partitionSyncBox.close();
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('File Move & Partition Sync Bug Reproduction Tests', () {
    test(
        'TC-MOVE-01: StorageRepository.moveFile captures oldFolderId in PendingAction payload',
        () async {
      final file = FileRecord(
        fileId: 'file_mov_1',
        name: 'video.mp4',
        metadataMessageId: 101,
        metadataFileId: 'meta_101',
        sizeMb: 25.0,
        mimeType: 'video/mp4',
        uploadedAt: DateTime.now(),
        chunkCount: 2,
        sha256Hash: 'hash',
        folderId: null, // in root
      );
      await hiveService.saveFile(file);

      syncQueue = _MockSyncQueueService();
      ServiceLocator.instance.setSyncQueueForTesting(syncQueue!);
      final repo = StorageRepository(
        hiveService,
        _FakeFileManagerService(),
        _FakeMetadataService(),
      );

      await repo.moveFile('file_mov_1', 'folder_videos');

      expect(pendingBox.isNotEmpty, isTrue);
      final action = pendingBox.values.first;
      expect(action.actionType, AppConstants.actionMoveFile);
      // In the buggy code, 'oldFolderId' is missing from the payload!
      expect(action.payload.containsKey('oldFolderId'), isTrue,
          reason: 'Payload must contain oldFolderId before Hive was mutated');
      expect(action.payload['oldFolderId'], isNull,
          reason: 'Original folder was root (null)');
    });

    test(
        'TC-MOVE-02: Fresh install sync does not overwrite moved file back to root partition',
        () async {
      // Simulate Telegram state where file was moved to 'folder_videos',
      // but 'folder_root.json' still contains a stale ghost ref (messageId 100)
      // while recentFiles has the true location 'folder_videos' (messageId 150).
      final staleRootRef = FileRef(
        fileId: 'file_mov_2',
        metaFileId: 'meta_old',
        name: 'tutorial.mp4',
        folderId: null,
        sizeMb: 50.0,
        mimeType: 'video/mp4',
        uploadedAt: DateTime.now().toIso8601String(),
        metadataMessageId: 100, // old message id
      );

      final trueMovedRef = FileRef(
        fileId: 'file_mov_2',
        metaFileId: 'meta_new',
        name: 'tutorial.mp4',
        folderId: 'folder_videos', // true moved location!
        sizeMb: 50.0,
        mimeType: 'video/mp4',
        uploadedAt: DateTime.now().toIso8601String(),
        metadataMessageId: 150, // newer message id!
      );

      final mockMeta = AppMetadata(
        owner: 'test@user.com',
        storageUsedMb: 50.0,
        totalFiles: 1,
        metadataMessageId: 200,
        folders: [
          Folder(id: 'folder_videos', name: 'Videos', createdAt: DateTime.now()),
        ],
        folderPartitionsMap: {
          AppConstants.rootFolderPartitionId: 301,
          'folder_videos': 302,
        },
        recentFiles: [trueMovedRef],
        categories: {},
        lastSynced: DateTime.now(),
      );

      final rootPartition = FolderPartition(
        folderId: AppConstants.rootFolderPartitionId,
        messageId: 301,
        files: [staleRootRef], // ghost entry on Telegram!
      );

      final videoPartition = FolderPartition(
        folderId: 'folder_videos',
        messageId: 302,
        files: [trueMovedRef],
      );

      // Create a mock metadata service with these partitions
      final mockMetaService = _MockTestMetadataService(
        meta: mockMeta,
        partitions: {
          AppConstants.rootFolderPartitionId: rootPartition,
          'folder_videos': videoPartition,
        },
        telegram: mockTelegram,
      );

      final syncService = SyncService(mockMetaService, hiveService);

      // Execute fresh-install syncFromTelegram (Hive is completely empty initially)
      await syncService.syncFromTelegram();

      // Check Hive: where is file_mov_2?
      final syncedFile = hiveService.getFile('file_mov_2');
      expect(syncedFile, isNotNull);
      // In the buggy code, syncFolderPartition(root) ran and overwritten the file to folderId: null!
      expect(syncedFile!.folderId, 'folder_videos',
          reason:
              'Moved file must NOT be reverted to root partition by stale root sync');
    });
  });
}

class _MockTestMetadataService extends MetadataService {
  AppMetadata meta;
  Map<String, FolderPartition> partitions;

  _MockTestMetadataService({
    required this.meta,
    required this.partitions,
    required TelegramService telegram,
  }) : super(telegram);

  @override
  Future<AppMetadata> fetch() async => meta;

  @override
  Future<FolderPartition?> fetchFolderPartition(String folderId) async {
    return partitions[folderId];
  }

  @override
  Future<void> update(AppMetadata newMeta) async {
    meta = newMeta;
  }
}

class _FakeFileManagerService extends Fake implements FileManagerService {}
class _FakeMetadataService extends Fake implements MetadataService {}

class _MockSyncQueueService extends SyncQueueService {
  _MockSyncQueueService() : super(_FakeFileManagerService());

  @override
  Future<void> processQueue({bool force = false}) async {}
}


