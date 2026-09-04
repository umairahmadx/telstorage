/*
 * File: file_manager.dart
 * Description: Component and logic definition for file_manager.dart in TelStorage.
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../models/app_metadata.dart';
import '../models/folder_record.dart';
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import '../utils/thumbnail_helper_native.dart'
    if (dart.library.js_interop) '../utils/thumbnail_helper_web.dart';
import 'hive_service.dart';
import 'metadata_service.dart';
import 'service_locator.dart';
import 'telegram_service.dart';

class FolderNotEmptyException implements Exception {
  @override
  String toString() => 'Cannot delete folder: folder is not empty';
}

/// Handles all file and folder rename / move / delete operations.
/// Always downloads via file_id; never relies on getUpdates.
class FileManagerService {
  final MetadataService _meta;
  final TelegramService _telegram;
  final HiveService _hive;

  FileManagerService(this._meta, this._telegram, this._hive);

  MetadataService get metadataService => _meta;

  // ── Folder Operations ───────────────────────────────────────

  Future<void> createFolder(String name,
      {String? parentId, String? folderId}) async {
    final meta = await _meta.fetch();
    final folder = Folder(
      id: folderId ?? const Uuid().v4(),
      name: name,
      parentId: parentId,
      createdAt: DateTime.now(),
    );

    meta.folders.add(folder);
    await _meta.update(meta);
    await _hive.saveFolder(FolderRecord.fromFolder(folder));
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final meta = await _meta.fetch();
    final folder = meta.folders.where((f) => f.id == folderId).firstOrNull;
    if (folder == null) {
      throw Exception('Folder "$folderId" not found in remote metadata');
    }
    folder.name = newName;

    await _meta.update(meta);
    await _hive.renameFolder(folderId, newName);
  }

  Future<void> moveFolder(String folderId, String? parentId) async {
    final meta = await _meta.fetch();
    final folder = meta.folders.where((f) => f.id == folderId).firstOrNull;
    if (folder == null) {
      throw Exception('Folder "$folderId" not found in remote metadata');
    }
    folder.parentId = parentId;

    await _meta.update(meta);
    await _hive.moveFolder(folderId, parentId);
  }

  void _collectSubfolderIds(String folderId, Set<String> idsToDelete) {
    idsToDelete.add(folderId);
    for (final sub in _hive.subfolders(folderId)) {
      _collectSubfolderIds(sub.id, idsToDelete);
    }
  }

  /// Deletes a folder tree and all of its files in one queued sync action.
  /// File snapshots are supplied by the local-first repository because the
  /// local cache is removed before the queued remote operation runs.
  Future<void> deleteFolder(
    String folderId, {
    List<String> folderIds = const [],
    List<Map<String, dynamic>> fileSnapshots = const [],
  }) async {
    for (final snapshot in fileSnapshots) {
      await deleteFileRemoteOnly(
        fileId: snapshot['fileId'] as String,
        metadataMessageId: snapshot['metadataMessageId'] as int?,
        metadataFileId: snapshot['metadataFileId'] as String?,
        sizeMb: (snapshot['sizeMb'] as num?)?.toDouble() ?? 0,
        mimeType: snapshot['mimeType'] as String? ?? 'application/octet-stream',
        folderId: snapshot['folderId'] as String?,
      );
    }

    // The local cache has already been deleted by the optimistic repository,
    // so use the folder ID snapshot from the queued action for nested folders.
    final idsToDelete = folderIds.toSet();
    if (idsToDelete.isEmpty) {
      _collectSubfolderIds(folderId, idsToDelete);
    }

    final meta = await _meta.fetch();
    final handledFileIds =
        fileSnapshots.map((s) => s['fileId'] as String).toSet();

    // Clean up uncached folder partitions and remote files on Telegram
    for (final id in idsToDelete) {
      final partMsgId = meta.folderPartitionsMap[id];
      if (partMsgId != null) {
        final partition = await _meta.fetchFolderPartition(id);
        if (partition != null) {
          for (final ref in partition.files) {
            if (!handledFileIds.contains(ref.fileId)) {
              await _deleteRemoteFileMessages(
                ref.metadataMessageId,
                ref.metaFileId,
              );
              try {
                if (ServiceLocator.instance.isInitialized) {
                  await ServiceLocator.instance.thumbnailRepository
                      .evict(ref.fileId);
                } else {
                  await ThumbnailHelper.deleteCachedThumbnail(ref.fileId);
                }
              } catch (_) {}
              meta.totalFiles = (meta.totalFiles - 1).clamp(0, 10000000);
              meta.storageUsedMb = (meta.storageUsedMb - (ref.sizeMb ?? 0.0))
                  .clamp(0.0, 10000000.0);
              final category = _category(ref.mimeType ?? '');
              final catStat = meta.categories[category];
              if (catStat != null) {
                catStat.count = (catStat.count - 1).clamp(0, 10000000);
                catStat.sizeMb = (catStat.sizeMb - (ref.sizeMb ?? 0.0))
                    .clamp(0.0, 10000000.0);
              }
              handledFileIds.add(ref.fileId);
            }
          }
        }
        if (partMsgId > 0) {
          try {
            await _telegram.deleteMessage(partMsgId);
          } catch (_) {}
        }
        meta.folderPartitionsMap.remove(id);
      }
      await _hive.removeFolderPartitionMessageId(id);
    }

    meta.folders.removeWhere((f) => idsToDelete.contains(f.id));
    meta.recentFiles.removeWhere(
        (f) => f.folderId != null && idsToDelete.contains(f.folderId));

    await _meta.update(meta);
    for (final id in idsToDelete) {
      await _hive.deleteFolder(id);
    }
  }

  // ── File Operations ─────────────────────────────────────────

  /// Download file metadata JSON using permanent file_id.
  Future<Map<String, dynamic>> _fetchFileMeta(
    int? messageId,
    String? fileId,
  ) async {
    if (fileId != null && fileId.isNotEmpty) {
      final bytes = await _telegram.downloadByFileId(fileId);
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }
    throw StateError(
        'Cannot fetch remote metadata: file has no remote metadataFileId.');
  }

  Future<void> renameFile(String fileId, String newName) async {
    final record = _hive.getFile(fileId);
    if (record == null) return;

    // Download existing metadata via file_id (not message_id)
    final fileMeta = await _fetchFileMeta(
      record.metadataMessageId,
      record.metadataFileId,
    );
    fileMeta['name'] = newName;

    // Upload updated metadata and delete the old one
    final uploadResult = await _telegram.uploadBytesWithFileId(
      Uint8List.fromList(utf8.encode(jsonEncode(fileMeta))),
      '$fileId.json',
    );
    final newMsgId = uploadResult['message_id'] as int;
    final newMetaFileId = uploadResult['file_id'] as String;

    await _telegram.deleteMessage(record.metadataMessageId);
    await _hive.updateFile(
      fileId,
      name: newName,
      metadataMsgId: newMsgId,
      metadataFileId: newMetaFileId,
    );

    final updatedRef = FileRef(
      fileId: fileId,
      metaFileId: newMetaFileId,
      name: newName,
      folderId: record.folderId,
      sizeMb: record.sizeMb,
      mimeType: record.mimeType,
      uploadedAt: record.uploadedAt.toIso8601String(),
      chunkCount: record.chunkCount,
      sha256: record.sha256Hash,
      metadataMessageId: newMsgId,
      thumbnailFileId: record.thumbnailFileId,
    );
    await _meta.updateFileRef(updatedRef);
  }

  Future<void> moveFile(String fileId, String? newFolderId) async {
    final record = _hive.getFile(fileId);
    if (record == null) return;

    final oldFolderId = record.folderId;
    final fileMeta = await _fetchFileMeta(
      record.metadataMessageId,
      record.metadataFileId,
    );
    fileMeta['folder_id'] = newFolderId;

    final uploadResult = await _telegram.uploadBytesWithFileId(
      Uint8List.fromList(utf8.encode(jsonEncode(fileMeta))),
      '$fileId.json',
    );
    final newMsgId = uploadResult['message_id'] as int;
    final newMetaFileId = uploadResult['file_id'] as String;

    await _telegram.deleteMessage(record.metadataMessageId);
    await _hive.updateFile(
      fileId,
      folderId: newFolderId,
      clearFolderId: newFolderId == null,
      metadataMsgId: newMsgId,
      metadataFileId: newMetaFileId,
    );

    final updatedRef = FileRef(
      fileId: fileId,
      metaFileId: newMetaFileId,
      name: record.name,
      folderId: newFolderId,
      sizeMb: record.sizeMb,
      mimeType: record.mimeType,
      uploadedAt: record.uploadedAt.toIso8601String(),
      chunkCount: record.chunkCount,
      sha256: record.sha256Hash,
      metadataMessageId: newMsgId,
      thumbnailFileId: record.thumbnailFileId,
    );
    await _meta.updateFileRef(updatedRef, oldFolderId: oldFolderId);
  }

  Future<void> deleteFile(String fileId) async {
    final record = _hive.getFile(fileId);
    if (record == null) return;

    Map<String, dynamic>? fileMeta;
    if (record.metadataFileId != null && record.metadataFileId!.isNotEmpty) {
      try {
        fileMeta = await _fetchFileMeta(
          record.metadataMessageId,
          record.metadataFileId,
        );
      } catch (e) {
        AppLogger.w('Could not fetch remote chunk metadata for $fileId: $e',
            tag: 'FileManager');
      }
    }

    if (fileMeta != null) {
      final chunks = fileMeta['chunks'] as List? ?? [];
      for (final chunk in chunks) {
        try {
          await _telegram.deleteMessage(chunk['message_id'] as int);
        } catch (_) {}
      }
      final thumbMsgId = fileMeta['thumbnail_message_id'] as int?;
      if (thumbMsgId != null && thumbMsgId > 0) {
        try {
          await _telegram.deleteMessage(thumbMsgId);
        } catch (_) {}
      }
    }

    if (record.metadataMessageId > 0) {
      try {
        await _telegram.deleteMessage(record.metadataMessageId);
      } catch (_) {}
    }

    try {
      final meta = await _meta.fetch();
      await _meta.removeFile(
        meta,
        fileId,
        record.sizeMb,
        record.mimeType,
        folderId: record.folderId,
      );
    } catch (e) {
      AppLogger.w('Could not remove file $fileId from remote partition: $e',
          tag: 'FileManager');
    }

    await _hive.deleteFile(fileId);
    try {
      if (ServiceLocator.instance.isInitialized) {
        await ServiceLocator.instance.thumbnailRepository.evict(fileId);
      } else {
        await ThumbnailHelper.deleteCachedThumbnail(fileId);
      }
    } catch (_) {}
    AppLogger.i('File $fileId deleted successfully', tag: 'FileManager');
  }

  Future<void> deleteFileRemoteOnly({
    required String fileId,
    required int? metadataMessageId,
    required String? metadataFileId,
    required double sizeMb,
    required String mimeType,
    String? folderId,
  }) async {
    await _deleteRemoteFileMessages(metadataMessageId, metadataFileId);
    try {
      if (ServiceLocator.instance.isInitialized) {
        await ServiceLocator.instance.thumbnailRepository.evict(fileId);
      } else {
        await ThumbnailHelper.deleteCachedThumbnail(fileId);
      }
    } catch (_) {}

    try {
      final meta = await _meta.fetch();
      await _meta.removeFile(meta, fileId, sizeMb, mimeType,
          folderId: folderId);
      AppLogger.i(
          'File $fileId deleted from remote metadata index successfully',
          tag: 'FileManager');
    } catch (e) {
      AppLogger.e('Failed to remove $fileId from global metadata: $e',
          tag: 'FileManager');
      rethrow;
    }
  }

  Future<void> _deleteRemoteFileMessages(
    int? metadataMessageId,
    String? metadataFileId,
  ) async {
    if (metadataMessageId != null && metadataMessageId > 0) {
      try {
        final fileMeta =
            await _fetchFileMeta(metadataMessageId, metadataFileId);
        final chunks = fileMeta['chunks'] as List? ?? [];
        for (final chunk in chunks) {
          try {
            await _telegram.deleteMessage(chunk['message_id'] as int);
          } catch (_) {}
        }
        final thumbMsgId = fileMeta['thumbnail_message_id'] as int?;
        if (thumbMsgId != null && thumbMsgId > 0) {
          try {
            await _telegram.deleteMessage(thumbMsgId);
          } catch (_) {}
        }
        await _telegram.deleteMessage(metadataMessageId);
      } catch (e) {
        AppLogger.w(
            'Could not clean up remote Telegram messages: $e',
            tag: 'FileManager');
      }
    }
  }

  String _category(String mimeType) {
    if (mimeType.startsWith('image/')) return 'images';
    if (mimeType.startsWith('video/')) return 'videos';
    if (mimeType.startsWith('audio/')) return 'audio';
    final isDoc = mimeType == 'application/pdf' ||
        mimeType.contains('document') ||
        mimeType.contains('text') ||
        mimeType.contains('sheet') ||
        mimeType.contains('presentation');
    if (isDoc) return 'documents';
    final isArchive = mimeType.contains('zip') ||
        mimeType.contains('compressed') ||
        mimeType.contains('tar') ||
        mimeType.contains('rar') ||
        mimeType.contains('7z');
    if (isArchive) return 'archives';
    return 'others';
  }

  Future<void> copyFile({
    required String originalFileId,
    required String newFileId,
    required String newName,
    required String? targetFolderId,
  }) async {
    final record = _hive.getFile(originalFileId);
    if (record == null) return;

    final fileMeta = await _fetchFileMeta(
      record.metadataMessageId,
      record.metadataFileId,
    );

    fileMeta['id'] = newFileId;
    fileMeta['name'] = newName;
    fileMeta['folder_id'] = targetFolderId;
    fileMeta['uploaded_at'] = DateTime.now().toIso8601String();

    final uploadResult = await _telegram.uploadBytesWithFileId(
      Uint8List.fromList(utf8.encode(jsonEncode(fileMeta))),
      '$newFileId.json',
    );

    final newMsgId = uploadResult['message_id'] as int;
    final newMetaFileId = uploadResult['file_id'] as String;

    final copyRecord = FileRecord(
      fileId: newFileId,
      metadataMessageId: newMsgId,
      metadataFileId: newMetaFileId,
      thumbnailFileId: record.thumbnailFileId,
      name: newName,
      sizeMb: record.sizeMb,
      mimeType: record.mimeType,
      uploadedAt: DateTime.now(),
      folderId: targetFolderId,
      chunkCount: record.chunkCount,
      sha256Hash: record.sha256Hash,
    );

    await _hive.saveFile(copyRecord);

    final newRef = FileRef(
      fileId: newFileId,
      metaFileId: newMetaFileId,
      name: newName,
      folderId: targetFolderId,
      sizeMb: record.sizeMb,
      mimeType: record.mimeType,
      uploadedAt: copyRecord.uploadedAt.toIso8601String(),
      chunkCount: record.chunkCount,
      sha256: record.sha256Hash,
      metadataMessageId: newMsgId,
      thumbnailFileId: record.thumbnailFileId,
    );
    await _meta.addFileRef(newRef, record.sizeMb, record.mimeType);
  }
}
