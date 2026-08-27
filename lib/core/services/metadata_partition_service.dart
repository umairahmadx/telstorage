/*
 * File: metadata_partition_service.dart
 * Description: Component and logic definition for metadata_partition_service.dart in TelStorage.
 */

import 'dart:convert';
import 'dart:typed_data';
import '../models/app_metadata.dart';
import '../models/folder_partition.dart';
import '../utils/app_logger.dart';
import 'lru_folder_cache_service.dart';
import 'telegram_service.dart';

/// Helper service for managing folder partition JSON files on Telegram.
class MetadataPartitionService {
  final TelegramService _telegram;

  MetadataPartitionService(this._telegram);

  /// Fetch a folder's metadata partition on-demand via LRU cache
  Future<FolderPartition?> fetchFolderPartition(
    String folderId,
    Future<AppMetadata> Function() fetchAppMeta,
  ) async {
    final cached = LruFolderCacheService.instance.get(folderId);
    if (cached != null) return cached;

    final appMeta = await fetchAppMeta();
    final messageId = appMeta.folderPartitionsMap[folderId];
    if (messageId == null) return null;

    try {
      final fileId = await _telegram.getFileIdOfMessage(messageId);
      final jsonBytes = await _telegram.downloadByFileId(fileId);
      final jsonStr = utf8.decode(jsonBytes);
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final partition = FolderPartition.fromJson(jsonMap, messageId);

      LruFolderCacheService.instance.put(folderId, partition);
      return partition;
    } catch (e) {
      AppLogger.e('Failed to fetch folder partition $folderId: $e',
          tag: 'MetadataPartitionService');
      return null;
    }
  }

  /// Write updated FileRefs to a folder partition file on Telegram.
  Future<void> saveFileRefsToPartition(
    AppMetadata meta,
    String folderId,
    List<FileRef> newRefs,
  ) async {
    FolderPartition? existingPartition =
        LruFolderCacheService.instance.get(folderId);
    if (existingPartition == null &&
        meta.folderPartitionsMap.containsKey(folderId)) {
      try {
        existingPartition =
            await fetchFolderPartition(folderId, () async => meta);
      } catch (_) {}
    }
    existingPartition ??=
        FolderPartition(folderId: folderId, messageId: 0, files: []);

    final updatedFiles = List<FileRef>.from(existingPartition.files);
    for (final ref in newRefs) {
      updatedFiles.removeWhere((f) => f.fileId == ref.fileId);
      updatedFiles.add(ref);
    }

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'folder_id': folderId,
      'files': updatedFiles.map((r) => r.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    })));

    final result = await _telegram.uploadBytesWithFileId(
      bytes,
      'folder_$folderId.json',
    );
    final msgId = result['message_id'] as int;

    LruFolderCacheService.instance.put(
      folderId,
      FolderPartition(
          folderId: folderId, messageId: msgId, files: updatedFiles),
    );
    meta.folderPartitionsMap[folderId] = msgId;

    if (existingPartition.messageId > 0) {
      try {
        await _telegram.deleteMessage(existingPartition.messageId);
      } catch (_) {}
    }
  }
}
