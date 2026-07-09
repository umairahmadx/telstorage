import 'package:uuid/uuid.dart';
import '../../../../core/models/pending_action.dart';
import '../../../../core/models/file_record.dart';
import '../../../../core/models/folder_record.dart';
import '../../../../core/services/hive_service.dart';
import '../../../../core/services/file_manager.dart';
import '../../../../core/utils/connectivity.dart';
import '../../../../core/constants/app_constants.dart';
import 'package:hive/hive.dart';

class StorageRepository {
  final HiveService _hive;
  final FileManagerService _fileManager;

  StorageRepository(
    this._hive,
    this._fileManager,
  );

  Box<PendingAction> get _pendingBox =>
      Hive.box<PendingAction>(AppConstants.pendingActionsBox);

  // ── Read Operations (Offline-First) ───────────────────────────────────

  List<FolderRecord> getFolders(String? parentId) {
    return _hive.subfolders(parentId);
  }

  List<FileRecord> getFiles(String? folderId) {
    return _hive.filesInFolder(folderId);
  }

  List<FileRecord> getRecentFiles(int limit) {
    return _hive.recentFiles(limit);
  }

  // ── Mutating Operations (Sync / Queue offline) ────────────────────────

  Future<void> createFolder(String name, {String? parentId}) async {
    if (await Connectivity.hasConnection()) {
      await _fileManager.createFolder(name, parentId: parentId);
    } else {
      final folderId = const Uuid().v4();
      final folder = FolderRecord(
        id: folderId,
        name: name,
        parentId: parentId,
        createdAt: DateTime.now(),
      );
      await _hive.saveFolder(folder);

      final pending = PendingAction(
        id: const Uuid().v4(),
        actionType: 'createFolder',
        payload: {
          'id': folderId,
          'name': name,
          'parentId': parentId,
        },
        timestamp: DateTime.now(),
      );
      await _pendingBox.put(pending.id, pending);
    }
  }

  Future<void> renameFolder(String folderId, String newName) async {
    if (await Connectivity.hasConnection()) {
      await _fileManager.renameFolder(folderId, newName);
    } else {
      await _hive.renameFolder(folderId, newName);

      final pending = PendingAction(
        id: const Uuid().v4(),
        actionType: 'renameFolder',
        payload: {
          'folderId': folderId,
          'name': newName,
        },
        timestamp: DateTime.now(),
      );
      await _pendingBox.put(pending.id, pending);
    }
  }

  Future<void> deleteFolder(String folderId) async {
    final hasFiles = _hive.filesInFolder(folderId).isNotEmpty ||
        _hive.subfolders(folderId).isNotEmpty;
    if (hasFiles) throw FolderNotEmptyException();

    if (await Connectivity.hasConnection()) {
      await _fileManager.deleteFolder(folderId);
    } else {
      await _hive.deleteFolder(folderId);

      final pending = PendingAction(
        id: const Uuid().v4(),
        actionType: 'deleteFolder',
        payload: {
          'folderId': folderId,
        },
        timestamp: DateTime.now(),
      );
      await _pendingBox.put(pending.id, pending);
    }
  }

  Future<void> renameFile(String fileId, String newName) async {
    if (await Connectivity.hasConnection()) {
      await _fileManager.renameFile(fileId, newName);
    } else {
      await _hive.updateFile(fileId, name: newName);

      final pending = PendingAction(
        id: const Uuid().v4(),
        actionType: 'renameFile',
        payload: {
          'fileId': fileId,
          'name': newName,
        },
        timestamp: DateTime.now(),
      );
      await _pendingBox.put(pending.id, pending);
    }
  }

  Future<void> moveFile(String fileId, String? newFolderId) async {
    if (await Connectivity.hasConnection()) {
      await _fileManager.moveFile(fileId, newFolderId);
    } else {
      await _hive.updateFile(
        fileId,
        folderId: newFolderId,
        clearFolderId: newFolderId == null,
      );

      final pending = PendingAction(
        id: const Uuid().v4(),
        actionType: 'moveFile',
        payload: {
          'fileId': fileId,
          'folderId': newFolderId,
        },
        timestamp: DateTime.now(),
      );
      await _pendingBox.put(pending.id, pending);
    }
  }

  Future<void> deleteFile(String fileId) async {
    final record = _hive.getFile(fileId);
    if (record == null) return;

    if (await Connectivity.hasConnection()) {
      await _fileManager.deleteFile(fileId);
    } else {
      // Offline: we need the file meta info to delete from Telegram later!
      // Since it's stored in the FileRecord, we serialize the necessary info in payload.
      final payload = {
        'fileId': fileId,
        'metadataMessageId': record.metadataMessageId,
        'metadataFileId': record.metadataFileId,
        'sizeMb': record.sizeMb,
        'mimeType': record.mimeType,
      };

      await _hive.deleteFile(fileId);

      final pending = PendingAction(
        id: const Uuid().v4(),
        actionType: 'deleteFile',
        payload: payload,
        timestamp: DateTime.now(),
      );
      await _pendingBox.put(pending.id, pending);
    }
  }
}
