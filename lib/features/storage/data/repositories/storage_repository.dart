import 'package:uuid/uuid.dart';
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

class StorageRepository {
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

  Future<void> enqueueDownload(FileRecord file) async {
    return ServiceLocator.instance.downloadQueue.enqueueDownload(file);
  }

  Future<void> enqueueWebShare(FileRecord file,
      {String? password, int? expiryDays}) async {
    return ServiceLocator.instance.webShareQueue
        .enqueueShare(file, password: password, expiryDays: expiryDays);
  }

  FileRecord? getFile(String fileId) {
    return _hive.getFile(fileId);
  }

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

  // ── Mutating Operations (Local-First Optimistic Execution) ─────────────

  Future<String> createFolder(String name, {String? parentId}) async {
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
    return folderId;
  }

  Future<void> renameFolder(String folderId, String newName) async {
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
  }

  Future<void> deleteFolder(String folderId) async {
    final hasFiles = _hive.filesInFolder(folderId).isNotEmpty ||
        _hive.subfolders(folderId).isNotEmpty;
    if (hasFiles) throw FolderNotEmptyException();

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
    _syncQueue.processQueue();
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

    final newFolderId = await createFolder(
      renameRoot ? '${folder.name}_copy' : folder.name,
      parentId: targetParentId,
    );

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

  Future<void> renameFile(String fileId, String newName) async {
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

  Future<void> copyFile(String fileId, String? targetFolderId) async {
    final original = _hive.getFile(fileId);
    if (original == null) return;

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
  }

  Future<void> deleteFile(String fileId) async {
    final record = _hive.getFile(fileId);
    if (record == null) return;

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
  }
}
