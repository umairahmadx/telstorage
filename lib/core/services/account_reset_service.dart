/*
 * File: account_reset_service.dart
 * Description: Clean account reset utility that wipes channel partitions, unpins metadata, and resets local Hive database to pristine condition.
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/models/pending_action.dart';
import 'package:telstorage/core/utils/app_logger.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/lru_folder_cache_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/telegram_service.dart';

/// Service performing total channel and local state reset for fresh starts.
class AccountResetService {
  final TelegramService _telegram;
  final MetadataService _metadata;
  final HiveService _hive;
  final FlutterSecureStorage _storage;

  /// Constructs AccountResetService.
  AccountResetService({
    required TelegramService telegram,
    required MetadataService metadata,
    required HiveService hive,
    FlutterSecureStorage? storage,
  })  : _telegram = telegram,
        _metadata = metadata,
        _hive = hive,
        _storage = storage ?? const FlutterSecureStorage();

  /// Wipes all channel messages recorded in metadata and re-initializes pristine state.
  Future<Result<void>> resetChannelAndLocalData({
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      onProgress?.call(0.1, 'Inspecting existing cloud metadata...');
      AppMetadata? currentMeta;
      try {
        currentMeta = await _metadata.fetch();
      } catch (e) {
        AppLogger.w('Could not fetch existing metadata before reset: $e',
            tag: 'AccountResetService');
      }

      // Collect remote messages to delete
      final messagesToDelete = <int>{};
      if (currentMeta != null) {
        if (currentMeta.metadataMessageId > 0) {
          messagesToDelete.add(currentMeta.metadataMessageId);
        }
        for (final msgId in currentMeta.folderPartitionsMap.values) {
          if (msgId > 0) messagesToDelete.add(msgId);
        }
        for (final ref in currentMeta.recentFiles) {
          if (ref.metadataMessageId != null && ref.metadataMessageId! > 0) {
            messagesToDelete.add(ref.metadataMessageId!);
          }
        }
      }

      onProgress?.call(0.3, 'Deleting remote partition and metadata files...');
      for (final msgId in messagesToDelete) {
        try {
          await _telegram.deleteMessage(msgId);
        } catch (_) {}
      }

      onProgress?.call(0.5, 'Unpinning all channel messages...');
      try {
        await _telegram.unpinAllMessages();
      } catch (_) {}

      onProgress?.call(0.7, 'Flushing local database and memory caches...');
      await _hive.clearAll();
      if (Hive.isBoxOpen(AppConstants.pendingActionsBox)) {
        await Hive.box<PendingAction>(AppConstants.pendingActionsBox).clear();
      }
      LruFolderCacheService.instance.clear();

      onProgress?.call(0.85, 'Initializing pristine manifest...');
      final ownerEmail =
          await _storage.read(key: AppConstants.keyEmail) ?? 'user@telstorage.com';

      // Build pristine AppMetadata
      final freshMeta = AppMetadata(
        owner: ownerEmail,
        storageUsedMb: 0.0,
        totalFiles: 0,
        metadataMessageId: 0,
        folders: [],
        categories: {
          'images': CategoryStat(count: 0, sizeMb: 0.0),
          'videos': CategoryStat(count: 0, sizeMb: 0.0),
          'documents': CategoryStat(count: 0, sizeMb: 0.0),
          'audio': CategoryStat(count: 0, sizeMb: 0.0),
          'archives': CategoryStat(count: 0, sizeMb: 0.0),
          'others': CategoryStat(count: 0, sizeMb: 0.0),
        },
        lastSynced: DateTime.now(),
      );

      // Create initial empty root folder partition
      final rootBytes = Uint8List.fromList(utf8.encode(jsonEncode({
        'folder_id': AppConstants.rootFolderPartitionId,
        'files': [],
        'updated_at': DateTime.now().toIso8601String(),
      })));

      final rootResult = await _telegram.uploadBytesWithFileId(
        rootBytes,
        'folder_${AppConstants.rootFolderPartitionId}.json',
      );
      final rootMsgId = rootResult['message_id'] as int;
      freshMeta.folderPartitionsMap[AppConstants.rootFolderPartitionId] = rootMsgId;

      // Upload and pin fresh metadata
      final metaBytes =
          Uint8List.fromList(utf8.encode(jsonEncode(freshMeta.toJson())));
      final metaResult = await _telegram.uploadBytesWithFileId(
        metaBytes,
        AppConstants.metadataFileName,
      );
      final metaMsgId = metaResult['message_id'] as int;
      final metaFileId = metaResult['file_id'] as String;

      await _telegram.pinMessage(metaMsgId);
      await _storage.write(
          key: AppConstants.keyMetadataMessageId, value: metaMsgId.toString());
      await _storage.write(
          key: AppConstants.keyMetadataFileId, value: metaFileId);

      await _hive.setFolderPartitionMessageId(
          AppConstants.rootFolderPartitionId, rootMsgId);

      onProgress?.call(1.0, 'Account reset complete!');
      AppLogger.i('Channel reset successfully to pristine state.',
          tag: 'AccountResetService');
      return const Success(null);
    } catch (e, stack) {
      AppLogger.e('Failed to reset channel data: $e',
          tag: 'AccountResetService', error: e, stackTrace: stack);
      return Failure(UnknownFailure('Account reset failed: $e', e));
    }
  }
}
