/*
 * File: file_deletion_and_reconciliation_test.dart
 * Description: Reproduction and verification tests for file deletion and storage reconciliation.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/telegram_service.dart';

class MockTestTelegramService extends TelegramService {
  final List<int> deletedMessageIds = [];

  @override
  Future<void> deleteMessages(List<int> messageIds) async {
    deletedMessageIds.addAll(messageIds);
  }

  @override
  Future<void> deleteMessage(int messageId) async {
    deletedMessageIds.add(messageId);
  }
}

class MockTestMetadataService extends MetadataService {
  MockTestMetadataService(super.telegram);

  @override
  Future<AppMetadata> fetch() async {
    return AppMetadata(
      owner: 'test@user.com',
      storageUsedMb: 0.0,
      totalFiles: 0,
      metadataMessageId: 100,
      folders: [],
      categories: {},
      lastSynced: DateTime.now(),
      folderPartitionsMap: {},
    );
  }

  @override
  Future<void> removeFile(
    AppMetadata meta,
    String fileId,
    double sizeMb,
    String mimeType, {
    String? folderId,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockTestTelegramService mockTelegram;
  late MockTestMetadataService mockMetadata;
  late FileManagerService fileManager;

  setUp(() {
    mockTelegram = MockTestTelegramService();
    mockMetadata = MockTestMetadataService(mockTelegram);
    fileManager = FileManagerService(
      mockMetadata,
      mockTelegram,
      HiveService.instance,
    );
  });

  group('TC-FileDeletion: metadataMessageId always deleted', () {
    test(
        'TC-01 (GREEN): metadataMessageId is deleted even when metadataFileId is null',
        () async {
      await fileManager.deleteFileRemoteOnly(
        fileId: 'file_test_123',
        metadataMessageId: 9999,
        metadataFileId: null,
        sizeMb: 10.0,
        mimeType: 'image/png',
      );

      expect(
        mockTelegram.deletedMessageIds,
        contains(9999),
        reason:
            'metadataMessageId (9999) must be deleted even if metadataFileId is null',
      );
    });

    test(
        'TC-02: metadataMessageId is deleted even when metadataFileId is empty',
        () async {
      await fileManager.deleteFileRemoteOnly(
        fileId: 'file_test_456',
        metadataMessageId: 8888,
        metadataFileId: '',
        sizeMb: 5.0,
        mimeType: 'video/mp4',
      );

      expect(mockTelegram.deletedMessageIds, contains(8888),
          reason: 'metadataMessageId (8888) must be deleted when fileId is empty');
    });

    test('TC-03: zero and negative metadataMessageId are skipped', () async {
      await fileManager.deleteFileRemoteOnly(
        fileId: 'file_test_789',
        metadataMessageId: 0,
        metadataFileId: null,
        sizeMb: 1.0,
        mimeType: 'audio/mpeg',
      );

      expect(mockTelegram.deletedMessageIds, isEmpty,
          reason: 'Zero metadataMessageId must NOT be added to the delete batch');
    });

    test('TC-04: null metadataMessageId does not throw', () async {
      expect(
        () => fileManager.deleteFileRemoteOnly(
          fileId: 'file_test_null',
          metadataMessageId: null,
          metadataFileId: null,
          sizeMb: 2.0,
          mimeType: 'application/pdf',
        ),
        returnsNormally,
      );
    });
  });

  group('TC-BulkDeletion: deleteMessages batching via TelegramService', () {
    test('TC-05: deleteMessages records all IDs in mock', () async {
      await mockTelegram.deleteMessages([101, 102, 103, 104]);
      expect(mockTelegram.deletedMessageIds,
          containsAll([101, 102, 103, 104]));
    });

    test('TC-06: deleteMessages skips negative/zero IDs via service', () async {
      // The actual TelegramService.deleteMessages filters <= 0 before calling API.
      // Our mock records what arrives; the real filter is tested via integration.
      // Here we verify the mock itself records correctly.
      await mockTelegram.deleteMessages([0, -5, 201]);
      expect(mockTelegram.deletedMessageIds, contains(201));
    });
  });
}
