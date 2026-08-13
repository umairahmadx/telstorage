import 'package:uuid/uuid.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/events/domain_event_bus.dart';
import '../../../../core/models/pending_action.dart';
import '../../../../core/models/file_record.dart';
import '../../../../core/models/folder_record.dart';
import '../../../../core/models/app_metadata.dart';
import '../../../../core/services/hive_service.dart';
import '../../../../core/services/file_manager.dart';
import '../../../../core/services/metadata_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/sync_queue_service.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/models/web_share_job.dart';
import 'package:hive/hive.dart';

import '../../domain/repositories/storage_repository_contract.dart';

class StorageRepository implements StorageRepositoryContract {
  final HiveService _hive;
  final FileManagerService fileManager;
  final MetadataService _metadataService;

  StorageRepository(
    this._hive,
    this.fileManager,
    this._metadataService,
  );

  Box<PendingAction> get _pendingBox =>
      Hive.box<PendingAction>(AppConstants.pendingActionsBox);

  SyncQueueService get _syncQueue => ServiceLocator.instance.syncQueue;
  SyncQueueService get syncQueue => ServiceLocator.instance.syncQueue;

  // ── Stats & Metadata ──────────────────────────────────────────────────

  Future<AppMetadata> getAppMetadata() async {
    return _metadataService.fetch();
  }

  Map<String, int> getCategoryCounts() {
    return _hive.categoryCount;
  }

  double getTotalSizeMb() {
    return _hive.totalSizeMb;
  }

  int getTotalFiles() {
    return _hive.totalFiles;
  }

  Future<String?> getUserEmail() async {
    return AuthService.instance.getEmail();
  }

  Future<Map<String, dynamic>> getWebShareQuota() async {
    return ServiceLocator.instance.webShareQueue.getBandwidthStatus();
  }

  int getTotalShares() {
    return ServiceLocator.instance.webShareQueue.allShares.length;
  }

  WebShareJob? getWebShareJob(String fileId) {
    return ServiceLocator.instance.webShareQueue.allShares
        .where((s) => s.fileId == fileId)
        .firstOrNull;
  }

  int getTotalCompletedDownloads() {
    return ServiceLocator.instance.downloadQueue.allJobs
        .where((j) => j.isComplete)
        .length;
  }

  @override
  List<FileRecord> get currentFiles => _hive.allFiles;

  @override
  List<FolderRecord> get currentFolders => _hive.allFolders;

  @override
  Future<Result<void>> enqueueDownload(FileRecord file) async {
    try {
      await ServiceLocator.instance.downloadQueue.enqueueDownload(file);
      return const Success(null);
    } catch (e) {
      return Failure(UnknownFailure(e.toString(), e));
    }
  }

  @override
  Future<Result<void>> enqueueWebShare(FileRecord file,
      {String? password, int? expiryDays, String? vanitySlug}) async {
    try {
      await ServiceLocator.instance.webShareQueue.enqueueShare(
        file,
        password: password,
        expiryDays: expiryDays,
        vanitySlug: vanitySlug,
      );
      return const Success(null);
    } catch (e) {
      return Failure(UnknownFailure(e.toString(), e));
    }
  }

  @override
  FileRecord? getFile(String fileId) {
    return _hive.getFile(fileId);
  }

  @override
  FolderRecord? getFolder(String folderId) {
    return _hive.getFolder(folderId);
  }

  int getFilesInFolderCount(String folderId) {
    return _hive.filesInFolder(folderId).length;
  }

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

  /// Returns all folders below [folderId], including the selected folder.
  Set<String> _folderTreeIds(String folderId) {
    final ids = <String>{};
    void collect(String id) {
      if (!ids.add(id)) return;
      for (final child in _hive.subfolders(id)) {
        collect(child.id);
      }
    }

    collect(folderId);
    return ids;
  }

  int getFolderDescendantFileCount(String folderId) {
    final ids = _folderTreeIds(folderId);
    return _hive.allFiles.where((file) => ids.contains(file.folderId)).length;
  }

  int getFolderDescendantFolderCount(String folderId) {
    return _folderTreeIds(folderId).length;
  }

  // ── Mutating Operations (Local-First Optimistic Execution) ─────────────

  @override
  Future<Result<String>> createFolder(String name, {String? parentId}) async {
    try {
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
      _syncQueue.processQueue();
      DomainEventBus.instance.fire(FolderCreatedEvent(folderId, name));
      return Success(folderId);
    } catch (e) {
      return Failure(UnknownFailure(e.toString(), e));
    }
  }

  @override
  Future<Result<void>> renameFolder(String folderId, String newName) async {
    try {
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
      _syncQueue.processQueue();
      DomainEventBus.instance.fire(FolderRenamedEvent(folderId, newName));
      return const Success(null);
    } catch (e) {
      return Failure(UnknownFailure(e.toString(), e));
    }
  }

  @override
  Future<Result<void>> deleteFolder(String folderId) async {
    try {
      final folderIds = _folderTreeIds(folderId);
      final files = _hive.allFiles
          .where((file) => folderIds.contains(file.folderId))
          .toList();

      final pending = PendingAction(
        id: const Uuid().v4(),
        actionType: 'deleteFolder',
        payload: {
          'folderId': folderId,
          'folderIds': folderIds.toList(),
          'fileSnapshots': files
              .map((file) => {
                    'fileId': file.fileId,
                    'metadataMessageId': file.metadataMessageId,
                    'metadataFileId': file.metadataFileId,
                    'sizeMb': file.sizeMb,
                    'mimeType': file.mimeType,
                    'folderId': file.folderId,
                  })
              .toList(),
        },
        timestamp: DateTime.now(),
      );

      // Optimistic local deletion includes every descendant file and folder.
      for (final file in files) {
        await _hive.deleteFile(file.fileId);
      }
      for (final id in folderIds) {
        await _hive.deleteFolder(id);
      }
      await _pendingBox.put(pending.id, pending);
      _syncQueue.processQueue();
      DomainEventBus.instance.fire(FolderDeletedEvent(folderId));
      return const Success(null);
    } catch (e) {
      return Failure(UnknownFailure(e.toString(), e));
    }
  }

  Future<void> moveFolder(String folderId, String? newParentId) async {
    if (folderId == newParentId || _isDescendant(newParentId, folderId)) {
      throw StateError('Cannot move a folder into itself.');
    }

    await _hive.moveFolder(folderId, newParentId);

    final pending = PendingAction(
      id: const Uuid().v4(),
      actionType: 'moveFolder',
      payload: {
        'folderId': folderId,
        'parentId': newParentId,
      },
      timestamp: DateTime.now(),
    );
    await _pendingBox.put(pending.id, pending);
    _syncQueue.processQueue();
  }

  Future<void> copyFolder(String folderId, String? targetParentId) async {
    if (folderId == targetParentId || _isDescendant(targetParentId, folderId)) {
      throw StateError('Cannot copy a folder into itself.');
    }

    await _copyFolderRecursive(folderId, targetParentId, renameRoot: true);
  }

  Future<String?> _copyFolderRecursive(
    String folderId,
    String? targetParentId, {
    bool renameRoot = false,
  }) async {
    final folder = _hive.getFolder(folderId);
    if (folder == null) return null;

    final createRes = await createFolder(
      renameRoot ? '${folder.name}_copy' : folder.name,
      parentId: targetParentId,
    );
    final newFolderId = createRes.dataOrNull;
    if (newFolderId == null) return null;

    for (final file in _hive.filesInFolder(folderId)) {
      await copyFile(file.fileId, newFolderId);
    }

    for (final child in _hive.subfolders(folderId)) {
      await _copyFolderRecursive(child.id, newFolderId);
    }

    return newFolderId;
  }

  bool _isDescendant(String? maybeChildId, String ancestorId) {
    var currentId = maybeChildId;
    while (currentId != null) {
      if (currentId == ancestorId) return true;
      currentId = _hive.getFolder(currentId)?.parentId;
    }
    return false;
  }

  @override
  Future<Result<void>> renameFile(String fileId, String newName) async {
    try {
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
      _syncQueue.processQueue();
      DomainEventBus.instance.fire(FileRenamedEvent(fileId, newName));
      return const Success(null);
    } catch (e) {
      return Failure(UnknownFailure(e.toString(), e));
    }
  }

  Future<void> moveFile(String fileId, String? newFolderId) async {
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
    _syncQueue.processQueue();
  }

  @override
  Future<Result<void>> copyFile(String fileId, String? targetFolderId) async {
    try {
      final original = _hive.getFile(fileId);
      if (original == null) {
        return const Failure(NotFoundFailure('Original file not found'));
      }

      final newFileId = const Uuid().v4();
      final nameParts = original.name.split('.');
      String newName;
      if (nameParts.length > 1 && original.name.contains('.')) {
        final ext = nameParts.removeLast();
        newName = '${nameParts.join('.')}_copy.$ext';
      } else {
        newName = '${original.name}_copy';
      }

      final copyRecord = FileRecord(
        fileId: newFileId,
        metadataMessageId: original.metadataMessageId,
        metadataFileId: original.metadataFileId,
        thumbnailFileId: original.thumbnailFileId,
        name: newName,
        sizeMb: original.sizeMb,
        mimeType: original.mimeType,
        uploadedAt: DateTime.now(),
        folderId: targetFolderId,
        chunkCount: original.chunkCount,
        sha256Hash: original.sha256Hash,
      );

      await _hive.saveFile(copyRecord);

      final pending = PendingAction(
        id: const Uuid().v4(),
        actionType: 'copyFile',
        payload: {
          'originalFileId': fileId,
          'newFileId': newFileId,
          'newName': newName,
          'targetFolderId': targetFolderId,
        },
        timestamp: DateTime.now(),
      );
      await _pendingBox.put(pending.id, pending);
      _syncQueue.processQueue();
      DomainEventBus.instance.fire(FileCopiedEvent(fileId, newFileId));
      return const Success(null);
    } catch (e) {
      return Failure(UnknownFailure(e.toString(), e));
    }
  }

  @override
  Future<Result<void>> deleteFile(String fileId) async {
    try {
      final record = _hive.getFile(fileId);
      if (record == null) {
        return const Failure(NotFoundFailure('File not found'));
      }

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
      _syncQueue.processQueue();
      DomainEventBus.instance.fire(FileDeletedEvent(fileId));
      return const Success(null);
    } catch (e) {
      return Failure(UnknownFailure(e.toString(), e));
    }
  }
}
