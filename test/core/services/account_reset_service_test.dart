/*
 * File: account_reset_service_test.dart
 * Description: Unit tests validating the AccountResetService channel wipe, unpinning, and pristine state re-initialization.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/pending_action.dart';
import 'package:telstorage/core/services/account_reset_service.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/telegram_service.dart';

class _FakeTelegramResetService extends TelegramService {
  final List<int> deletedMessageIds = [];
  bool unpinnedAll = false;
  int pinnedMsgId = 0;
  int uploadCount = 0;

  @override
  Future<void> deleteMessage(int messageId) async {
    deletedMessageIds.add(messageId);
  }

  @override
  Future<void> unpinAllMessages() async {
    unpinnedAll = true;
  }

  @override
  Future<void> pinMessage(int messageId) async {
    pinnedMsgId = messageId;
  }

  @override
  Future<Map<String, dynamic>> uploadBytesWithFileId(
    Uint8List bytes,
    String fileName, {
    void Function(double)? onProgress,
  }) async {
    uploadCount++;
    return {
      'message_id': 900 + uploadCount,
      'file_id': 'file-$uploadCount',
    };
  }
}

class _FakeMetadataResetService extends MetadataService {
  AppMetadata meta;

  _FakeMetadataResetService(this.meta, TelegramService telegram)
      : super(telegram);

  @override
  Future<AppMetadata> fetch() async => meta;
}

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<String?> read(
          {required String key,
          IOSOptions? iOptions,
          AndroidOptions? aOptions,
          LinuxOptions? lOptions,
          WebOptions? webOptions,
          MacOsOptions? mOptions,
          WindowsOptions? wOptions}) async =>
      _storage[key];

  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (value != null) _storage[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('reset_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FileRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(FolderRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(PendingActionAdapter());
    }

    await Hive.openBox<FileRecord>(AppConstants.filesBox);
    await Hive.openBox<FolderRecord>(AppConstants.foldersBox);
    await Hive.openBox<int>(AppConstants.partitionSyncBox);
    await Hive.openBox<PendingAction>(AppConstants.pendingActionsBox);
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test(
      'AccountResetService deletes messages, unpins, clears hive, and creates fresh metadata',
      () async {
    final fakeTelegram = _FakeTelegramResetService();
    final fakeStorage = _FakeSecureStorage();
    await fakeStorage.write(
        key: AppConstants.keyEmail, value: 'test@example.com');

    final meta = AppMetadata(
      owner: 'test@example.com',
      storageUsedMb: 100.0,
      totalFiles: 5,
      metadataMessageId: 10,
      folders: [
        Folder(
            id: 'f1',
            name: 'Old Folder',
            createdAt: DateTime.now(),
            itemCount: 2)
      ],
      folderPartitionsMap: {'root': 20, 'f1': 30},
      recentFiles: [
        FileRef(
          fileId: 'file-1',
          metaFileId: 'mf-1',
          name: 'file1.txt',
          metadataMessageId: 40,
        ),
      ],
      categories: {},
      lastSynced: DateTime.now(),
    );

    final fakeMetadata = _FakeMetadataResetService(meta, fakeTelegram);
    final hive = HiveService.instance;

    // Seed some local data
    await hive.saveFolder(FolderRecord(
      id: 'f1',
      name: 'Old Folder',
      createdAt: DateTime.now(),
      itemCount: 2,
    ));
    await hive.saveFile(FileRecord(
      fileId: 'file-1',
      name: 'file1.txt',
      folderId: 'f1',
      metadataMessageId: 40,
      sizeMb: 50.0,
      mimeType: 'text/plain',
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: '',
    ));

    expect(hive.totalFolders, 1);
    expect(hive.totalFiles, 1);

    final service = AccountResetService(
      telegram: fakeTelegram,
      metadata: fakeMetadata,
      hive: hive,
      storage: fakeStorage,
    );

    final result = await service.resetChannelAndLocalData();

    expect(result.isSuccess, isTrue);
    expect(fakeTelegram.unpinnedAll, isTrue);
    expect(fakeTelegram.deletedMessageIds, containsAll([10, 20, 30, 40]));
    expect(hive.totalFolders, 0);
    expect(hive.totalFiles, 0);

    // Verify fresh metadata was uploaded and pinned
    expect(fakeTelegram.pinnedMsgId, greaterThan(0));
    final savedMetaMsgId =
        await fakeStorage.read(key: AppConstants.keyMetadataMessageId);
    expect(savedMetaMsgId, isNotNull);
  });
}
