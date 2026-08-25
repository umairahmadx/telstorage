/*
 * File: app_constants_test.dart
 * Description: Unit tests validating AppConstants values, keys, box names, limits, and action types.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/constants/app_constants.dart';

void main() {
  group('AppConstants Validation Tests', () {
    test('TC-01: API & Base URLs are properly configured', () {
      expect(AppConstants.telegramApiBase, equals('https://api.telegram.org/bot'));
      expect(AppConstants.telegramFileBase, equals('https://api.telegram.org/file/bot'));
      expect(AppConstants.metadataFileName, equals('.metadata.json'));
      expect(AppConstants.partitionPrefix, equals('partition_'));
      expect(AppConstants.rootFolderPartitionId, equals('root'));
      expect(AppConstants.rootFolderSentinelId, equals('__root__'));
    });

    test('TC-02: Hive box names are unique and valid', () {
      final boxNames = [
        AppConstants.filesBox,
        AppConstants.foldersBox,
        AppConstants.downloadsBox,
        AppConstants.pendingActionsBox,
        AppConstants.webSharesBox,
      ];

      expect(boxNames.toSet().length, equals(boxNames.length),
          reason: 'All Hive box names must be distinct');
      expect(boxNames.every((name) => name.isNotEmpty), isTrue);
    });

    test('TC-03: Secure storage keys are distinct and non-empty', () {
      final keys = [
        AppConstants.keyBotToken,
        AppConstants.keyChannelId,
        AppConstants.keyEmail,
        AppConstants.keyMetadataMessageId,
        AppConstants.keyMetadataFileId,
      ];

      expect(keys.toSet().length, equals(keys.length),
          reason: 'All storage keys must be distinct');
      expect(keys.every((key) => key.isNotEmpty), isTrue);
    });

    test('TC-04: Offline sync pending action types are distinct', () {
      final actions = [
        AppConstants.actionCreateFolder,
        AppConstants.actionRenameFolder,
        AppConstants.actionDeleteFolder,
        AppConstants.actionMoveFolder,
        AppConstants.actionCopyFolder,
        AppConstants.actionRenameFile,
        AppConstants.actionMoveFile,
        AppConstants.actionCopyFile,
        AppConstants.actionDeleteFile,
        AppConstants.actionAddFileMeta,
      ];

      expect(actions.toSet().length, equals(actions.length),
          reason: 'All sync action types must be distinct');
      expect(actions.every((action) => action.isNotEmpty), isTrue);
    });

    test('TC-05: Storage, upload, chunk and cache limits are compliant', () {
      expect(AppConstants.maxUploadBytes, equals(50 * 1024 * 1024));
      expect(AppConstants.chunkSizeBytes, equals(19922944));
      expect(AppConstants.chunkSizeBytes, lessThan(20 * 1024 * 1024),
          reason: 'Chunk size must remain under 20MB for Telegram Bot API');
      expect(AppConstants.maxRecentFilesCount, equals(20));
      expect(AppConstants.lruFolderCacheCapacity, equals(30));
    });

    test('TC-06: Thumbnail generator specifications adhere to 400px and 50KB constraints', () {
      expect(AppConstants.thumbnailMaxDimension, equals(400));
      expect(AppConstants.thumbnailQuality, equals(80));
      expect(AppConstants.thumbnailMaxByteSize, equals(50 * 1024));
    });

    test('TC-07: Category filter identifiers are valid', () {
      final categories = [
        AppConstants.categoryImages,
        AppConstants.categoryVideos,
        AppConstants.categoryDocuments,
        AppConstants.categoryAudio,
        AppConstants.categoryArchives,
      ];

      expect(categories.toSet().length, equals(categories.length));
      expect(categories.every((c) => c.isNotEmpty), isTrue);
    });
  });
}
