import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../models/app_metadata.dart';
import '../models/folder_record.dart';
import '../utils/app_logger.dart';
import 'hive_service.dart';
import 'metadata_service.dart';
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

  // ── Folder Operations ───────────────────────────────────────

  Future<void> createFolder(String name, {String? parentId}) async {
    final meta = await _meta.fetch();
    final folder = Folder(
      id: const Uuid().v4(),
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
    final folder = meta.folders.firstWhere((f) => f.id == folderId);
    folder.name = newName;

    await _meta.update(meta);
    await _hive.renameFolder(folderId, newName);
  }

  Future<void> deleteFolder(String folderId) async {
    final hasFiles = _hive.filesInFolder(folderId).isNotEmpty;
    if (hasFiles) throw FolderNotEmptyException();

    final meta = await _meta.fetch();
    meta.folders.removeWhere((f) => f.id == folderId);

    await _meta.update(meta);
    await _hive.deleteFolder(folderId);
  }

  // ── File Operations ─────────────────────────────────────────

  /// Download file metadata JSON using permanent file_id (preferred) or
  /// message_id (legacy fallback).
  Future<Map<String, dynamic>> _fetchFileMeta(
    int messageId,
    String? fileId,
  ) async {
    Uint8List bytes;
    if (fileId != null && fileId.isNotEmpty) {
      bytes = await _telegram.downloadByFileId(fileId);
    } else {
      // Legacy: only works for very recent messages
      bytes = await _telegram.downloadBytes(messageId);
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
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

    // Update FileRef in global metadata
    final appMeta = await _meta.fetch();
    final ref = appMeta.files.where((f) => f.fileId == fileId).firstOrNull;
    if (ref != null) {
      appMeta.files.removeWhere((f) => f.fileId == fileId);
      appMeta.files.add(
        FileRef(
          fileId: fileId,
          metaFileId: newMetaFileId,
          name: newName,
          folderId: ref.folderId,
        ),
      );
      await _meta.update(appMeta);
    }
  }

  Future<void> moveFile(String fileId, String? newFolderId) async {
    final record = _hive.getFile(fileId);
    if (record == null) return;

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
  }

  Future<void> deleteFile(String fileId) async {
    final record = _hive.getFile(fileId);
    if (record == null) return;

    // ── Step 1: Download chunk list BEFORE deleting anything ────────────────
    // (old code deleted the metadata first, then tried to read it — that's
    //  the bug this fixes)
    late Map<String, dynamic> fileMeta;
    try {
      fileMeta = await _fetchFileMeta(
        record.metadataMessageId,
        record.metadataFileId,
      );
    } catch (e) {
      AppLogger.w(
        'Could not fetch metadata for $fileId — deleting from cache only. Error: $e',
        tag: 'FileManager',
      );
      // If we can't fetch metadata, still clean up local cache
      await _hive.deleteFile(fileId);
      return;
    }

    // ── Step 2: Delete each chunk from Telegram ──────────────────────────────
    final chunks = fileMeta['chunks'] as List? ?? [];
    for (final chunk in chunks) {
      try {
        await _telegram.deleteMessage(chunk['message_id'] as int);
      } catch (_) {
        // Ignore — chunk may already be deleted
      }
    }

    // ── Step 3: Delete metadata JSON from Telegram ───────────────────────────
    await _telegram.deleteMessage(record.metadataMessageId);

    // ── Step 4: Update global metadata ──────────────────────────────────────
    final meta = await _meta.fetch();
    await _meta.removeFile(meta, fileId, record.sizeMb, record.mimeType);

    // ── Step 5: Remove from local cache ─────────────────────────────────────
    await _hive.deleteFile(fileId);
    AppLogger.i('File $fileId deleted successfully', tag: 'FileManager');
  }
}
