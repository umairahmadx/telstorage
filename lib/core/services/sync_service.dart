/*
 * File: sync_service.dart
 * Description: Component and logic definition for sync_service.dart in TelStorage.
 */

import 'package:hive/hive.dart';
import '../constants/app_constants.dart';
import '../models/file_record.dart';
import '../models/folder_record.dart';
import '../models/pending_action.dart';
import '../models/app_metadata.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import 'hive_service.dart';
import 'metadata_service.dart';

/// Keeps the local Hive cache in sync with Telegram's global metadata partitions.
class SyncService {
  final MetadataService _metadata;
  final HiveService _hive;

  SyncService(this._metadata, this._hive);

  /// Merges Telegram partition truth → local Hive cache.
  Future<SyncResult> syncFromTelegram({
    Function(double progress, String status)? onProgress,
  }) async {
    int added = 0;
    int removed = 0;

    if (!await Connectivity.hasConnection()) {
      throw OfflineException('Cannot sync: no internet connection.');
    }

    try {
      onProgress?.call(0.0, 'Connecting to Telegram...');
      AppLogger.d('Starting full sync from Telegram...', tag: 'SyncService');

      final appMeta = await _metadata.fetch();

      // ── Pending Action Protection (Prevent State Reversion) ───────────────
      final Set<String> pendingDeletedFileIds = {};
      final Set<String> pendingDeletedFolderIds = {};
      final Set<String> pendingProtectedFileIds = {};
      final Set<String> pendingProtectedFolderIds = {};
      final Set<String> pendingRenamedOrMovedFileIds = {};
      final Set<String> pendingRenamedOrMovedFolderIds = {};

      try {
        if (Hive.isBoxOpen(AppConstants.pendingActionsBox)) {
          final pendingBox =
              Hive.box<PendingAction>(AppConstants.pendingActionsBox);
          for (final action in pendingBox.values) {
            final p = action.payload;
            final actionType = action.actionType;

            if (actionType == AppConstants.actionDeleteFile) {
              if (p['fileId'] != null) {
                pendingDeletedFileIds.add(p['fileId'].toString());
              }
            } else if (actionType == AppConstants.actionDeleteFolder) {
              if (p['folderId'] != null) {
                pendingDeletedFolderIds.add(p['folderId'].toString());
              }
              if (p['folderIds'] is List) {
                for (final id in p['folderIds'] as List) {
                  pendingDeletedFolderIds.add(id.toString());
                }
              }
              if (p['fileSnapshots'] is List) {
                for (final snap in p['fileSnapshots'] as List) {
                  if (snap is Map && snap['fileId'] != null) {
                    pendingDeletedFileIds.add(snap['fileId'].toString());
                  }
                }
              }
            } else if (actionType == AppConstants.actionRenameFile ||
                actionType == AppConstants.actionMoveFile) {
              if (p['fileId'] != null) {
                pendingRenamedOrMovedFileIds.add(p['fileId'].toString());
                pendingProtectedFileIds.add(p['fileId'].toString());
              }
            } else if (actionType == AppConstants.actionRenameFolder ||
                actionType == AppConstants.actionMoveFolder) {
              if (p['folderId'] != null) {
                pendingRenamedOrMovedFolderIds.add(p['folderId'].toString());
                pendingProtectedFolderIds.add(p['folderId'].toString());
              }
            } else if (actionType == AppConstants.actionCreateFolder) {
              if (p['id'] != null) {
                pendingProtectedFolderIds.add(p['id'].toString());
              }
              if (p['folderId'] != null) {
                pendingProtectedFolderIds.add(p['folderId'].toString());
              }
            } else if (actionType == AppConstants.actionCopyFile) {
              if (p['newFileId'] != null) {
                pendingProtectedFileIds.add(p['newFileId'].toString());
              }
            } else if (actionType == AppConstants.actionAddFileMeta) {
              if (p['fileMeta'] is Map && p['fileMeta']['file_id'] != null) {
                pendingProtectedFileIds
                    .add(p['fileMeta']['file_id'].toString());
              }
            }
          }
        }
      } catch (e) {
        AppLogger.w('Could not read pending actions box during sync: $e',
            tag: 'SyncService');
      }

      // ── Folders: add/update missing ───────────────────────────────────────
      onProgress?.call(0.05, 'Syncing folders...');
      AppLogger.d('${appMeta.folders.length} folder(s) on Telegram',
          tag: 'SyncService');
      for (final folder in appMeta.folders) {
        if (pendingDeletedFolderIds.contains(folder.id)) {
          AppLogger.d('Skipping pending deleted folder: ${folder.name}',
              tag: 'SyncService');
          continue;
        }

        final local = _hive.getFolder(folder.id);
        if (local == null) {
          await _hive.saveFolder(FolderRecord.fromFolder(folder));
          added++;
          AppLogger.d('Added folder: ${folder.name}', tag: 'SyncService');
        } else if (!pendingRenamedOrMovedFolderIds.contains(folder.id) &&
            (local.name != folder.name || local.parentId != folder.parentId)) {
          local.name = folder.name;
          local.parentId = folder.parentId;
          await local.save();
          AppLogger.d('Updated folder: ${folder.name}', tag: 'SyncService');
        }
      }

      // ── Folders: remove stale ──────────────────────────────────────────────
      final telegramFolderIds = appMeta.folders.map((f) => f.id).toSet();
      final localFolders = _hive.allFolders;
      for (final local in localFolders) {
        if (!telegramFolderIds.contains(local.id)) {
          if (pendingProtectedFolderIds.contains(local.id) ||
              pendingDeletedFolderIds.contains(local.id)) {
            AppLogger.d('Preserving local optimistic folder: ${local.name}',
                tag: 'SyncService');
            continue;
          }
          await _hive.deleteFolder(local.id);
          await _hive.removeFolderPartitionMessageId(local.id);
          removed++;
          AppLogger.d('Removed stale folder: ${local.name}',
              tag: 'SyncService');
        }
      }

      // ── Fast Bootstrap: Seed Recent Files ──────────────────────────────────
      onProgress?.call(0.3, 'Seeding recent files...');
      final List<FileRecord> recentRecords = [];
      for (final ref in appMeta.recentFiles) {
        if (pendingDeletedFileIds.contains(ref.fileId)) continue;
        final existing = _hive.getFile(ref.fileId);
        final name = pendingRenamedOrMovedFileIds.contains(ref.fileId) &&
                existing != null
            ? existing.name
            : ref.name;
        final folderId = pendingRenamedOrMovedFileIds.contains(ref.fileId) &&
                existing != null
            ? existing.folderId
            : ref.folderId;

        recentRecords.add(FileRecord(
          fileId: ref.fileId,
          name: name,
          folderId: folderId,
          metadataMessageId: ref.metadataMessageId ?? 0,
          metadataFileId: ref.metaFileId,
          sizeMb: ref.sizeMb ?? 0.0,
          mimeType: ref.mimeType ?? 'application/octet-stream',
          uploadedAt: ref.uploadedAt != null
              ? DateTime.tryParse(ref.uploadedAt!) ?? DateTime.now()
              : DateTime.now(),
          chunkCount: ref.chunkCount ?? 1,
          sha256Hash: ref.sha256 ?? '',
          thumbnailFileId: ref.thumbnailFileId ?? existing?.thumbnailFileId,
        ));
      }
      if (recentRecords.isNotEmpty) {
        await _hive.saveFilesBatch(recentRecords);
        AppLogger.d('Seeded ${recentRecords.length} recent files into local cache',
            tag: 'SyncService');
      }

      // ── Fast Bootstrap: Sync Root Folder Partition ────────────────────────
      onProgress?.call(0.6, 'Syncing root directory...');
      await syncFolderPartition(AppConstants.rootFolderPartitionId,
          meta: appMeta);

      onProgress?.call(1.0, 'Sync complete!');
      AppLogger.i(
          'Sync done — +$added added, -$removed removed. Local: ${_hive.totalFiles} files, ${_hive.totalFolders} folders',
          tag: 'SyncService');

      return SyncResult(added: added, removed: removed);
    } catch (e) {
      AppLogger.e('Sync failed: $e', tag: 'SyncService', error: e);
      rethrow;
    }
  }

  /// Syncs an individual folder partition on-demand with O(1) ETag caching.
  Future<bool> syncFolderPartition(
    String folderId, {
    AppMetadata? meta,
  }) async {
    if (!await Connectivity.hasConnection()) {
      throw OfflineException('Cannot sync folder: no internet connection.');
    }

    final appMeta = meta ?? await _metadata.fetch();
    final cloudMessageId = appMeta.folderPartitionsMap[folderId];
    final localMessageId = _hive.getFolderPartitionMessageId(folderId);

    // ETag Match: 0ms cache hit with zero network calls
    if (cloudMessageId != null && localMessageId == cloudMessageId) {
      AppLogger.d(
          'Partition $folderId up to date (ETag: $cloudMessageId)',
          tag: 'SyncService');
      return false;
    }

    final targetFolderId =
        folderId == AppConstants.rootFolderPartitionId ? null : folderId;

    final pendingSets = _getPendingSets();

    if (cloudMessageId == null) {
      // No partition in cloud yet (empty or newly created)
      _cleanStaleLocalFilesInFolder(targetFolderId, const {}, pendingSets);
      await _hive.setFolderPartitionMessageId(folderId, 0);
      return true;
    }

    final partition = await _metadata.fetchFolderPartition(folderId);
    if (partition == null) {
      _cleanStaleLocalFilesInFolder(targetFolderId, const {}, pendingSets);
      await _hive.setFolderPartitionMessageId(folderId, cloudMessageId);
      return true;
    }

    final List<FileRecord> records = [];
    final Set<String> partitionFileIds = {};

    for (final ref in partition.files) {
      partitionFileIds.add(ref.fileId);
      if (pendingSets.deletedFileIds.contains(ref.fileId)) continue;

      final existing = _hive.getFile(ref.fileId);
      final name = pendingSets.renamedOrMovedFileIds.contains(ref.fileId) &&
              existing != null
          ? existing.name
          : ref.name;
      final fId = pendingSets.renamedOrMovedFileIds.contains(ref.fileId) &&
              existing != null
          ? existing.folderId
          : targetFolderId;

      records.add(FileRecord(
        fileId: ref.fileId,
        name: name,
        folderId: fId,
        metadataMessageId: ref.metadataMessageId ?? 0,
        metadataFileId: ref.metaFileId,
        sizeMb: ref.sizeMb ?? 0.0,
        mimeType: ref.mimeType ?? 'application/octet-stream',
        uploadedAt: ref.uploadedAt != null
            ? DateTime.tryParse(ref.uploadedAt!) ?? DateTime.now()
            : DateTime.now(),
        chunkCount: ref.chunkCount ?? 1,
        sha256Hash: ref.sha256 ?? '',
        thumbnailFileId: ref.thumbnailFileId ?? existing?.thumbnailFileId,
      ));
    }

    await _cleanStaleLocalFilesInFolder(
        targetFolderId, partitionFileIds, pendingSets);
    await _hive.saveFilesBatch(records);
    await _hive.setFolderPartitionMessageId(folderId, cloudMessageId);

    AppLogger.i(
        'Synced partition $folderId: ${records.length} files (ETag: $cloudMessageId)',
        tag: 'SyncService');
    return true;
  }

  /// Ensures a folder and all of its descendant subfolders are indexed into Hive.
  Future<void> ensureFolderTreeSynced(String folderId) async {
    final folderIds = _collectDescendantFolderIds(folderId);
    folderIds.add(folderId);

    for (final fId in folderIds) {
      final isCached = _hive.getFolderPartitionMessageId(fId) != null;
      if (!isCached) {
        if (!await Connectivity.hasConnection()) {
          throw OfflineException('No internet connection');
        }
        await syncFolderPartition(fId);
      }
    }
  }

  Set<String> _collectDescendantFolderIds(String parentId) {
    final result = <String>{};
    final all = _hive.allFolders;
    void find(String pId) {
      for (final f in all) {
        if (f.parentId == pId && !result.contains(f.id)) {
          result.add(f.id);
          find(f.id);
        }
      }
    }

    find(parentId);
    return result;
  }

  Future<void> _cleanStaleLocalFilesInFolder(
    String? folderId,
    Set<String> validPartitionFileIds,
    _PendingSets pendingSets,
  ) async {
    final localFiles =
        _hive.allFiles.where((f) => f.folderId == folderId).toList();
    for (final local in localFiles) {
      if (!validPartitionFileIds.contains(local.fileId)) {
        if (pendingSets.protectedFileIds.contains(local.fileId) ||
            pendingSets.deletedFileIds.contains(local.fileId)) {
          continue;
        }
        if (DateTime.now().difference(local.uploadedAt).inMinutes < 15) {
          continue;
        }
        await _hive.deleteFile(local.fileId);
        AppLogger.d('Cleaned stale file: ${local.name}', tag: 'SyncService');
      }
    }
  }

  _PendingSets _getPendingSets() {
    final pendingDeletedFileIds = <String>{};
    final pendingProtectedFileIds = <String>{};
    final pendingRenamedOrMovedFileIds = <String>{};

    try {
      if (Hive.isBoxOpen(AppConstants.pendingActionsBox)) {
        final pendingBox =
            Hive.box<PendingAction>(AppConstants.pendingActionsBox);
        for (final action in pendingBox.values) {
          final p = action.payload;
          final actionType = action.actionType;

          if (actionType == AppConstants.actionDeleteFile &&
              p['fileId'] != null) {
            pendingDeletedFileIds.add(p['fileId'].toString());
          } else if (actionType == AppConstants.actionRenameFile ||
              actionType == AppConstants.actionMoveFile) {
            if (p['fileId'] != null) {
              pendingRenamedOrMovedFileIds.add(p['fileId'].toString());
              pendingProtectedFileIds.add(p['fileId'].toString());
            }
          } else if (actionType == AppConstants.actionCopyFile &&
              p['newFileId'] != null) {
            pendingProtectedFileIds.add(p['newFileId'].toString());
          } else if (actionType == AppConstants.actionAddFileMeta &&
              p['fileMeta'] is Map &&
              p['fileMeta']['file_id'] != null) {
            pendingProtectedFileIds.add(p['fileMeta']['file_id'].toString());
          }
        }
      }
    } catch (_) {}

    return _PendingSets(
      deletedFileIds: pendingDeletedFileIds,
      protectedFileIds: pendingProtectedFileIds,
      renamedOrMovedFileIds: pendingRenamedOrMovedFileIds,
    );
  }
}

class _PendingSets {
  final Set<String> deletedFileIds;
  final Set<String> protectedFileIds;
  final Set<String> renamedOrMovedFileIds;

  _PendingSets({
    required this.deletedFileIds,
    required this.protectedFileIds,
    required this.renamedOrMovedFileIds,
  });
}

class SyncResult {
  final int added;
  final int removed;
  SyncResult({required this.added, required this.removed});
  bool get hasChanges => added > 0 || removed > 0;
}
