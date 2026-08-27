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
          removed++;
          AppLogger.d('Removed stale folder: ${local.name}',
              tag: 'SyncService');
        }
      }

      // ── Files: build index from folder partitions ──────────────────────────
      final List<FileRef> fileRefs = [];
      for (final folderId in appMeta.folderPartitionsMap.keys) {
        if (pendingDeletedFolderIds.contains(folderId)) continue;
        final partition = await _metadata.fetchFolderPartition(folderId);
        if (partition != null) {
          fileRefs.addAll(partition.files);
        }
      }
      AppLogger.d('${fileRefs.length} file(s) on Telegram', tag: 'SyncService');

      // Add/update files in local Hive
      for (var i = 0; i < fileRefs.length; i++) {
        final ref = fileRefs[i];
        if (pendingDeletedFileIds.contains(ref.fileId)) {
          AppLogger.d('Skipping pending deleted file: ${ref.name}',
              tag: 'SyncService');
          continue;
        }

        onProgress?.call(
          0.1 + (i / fileRefs.length * 0.75),
          'Syncing ${i + 1}/${fileRefs.length}: ${ref.name}',
        );

        final existing = _hive.getFile(ref.fileId);
        if (existing != null) {
          bool updated = false;
          if (!pendingRenamedOrMovedFileIds.contains(ref.fileId)) {
            if (existing.name != ref.name ||
                existing.folderId != ref.folderId) {
              existing.name = ref.name;
              existing.folderId = ref.folderId;
              updated = true;
            }
          }
          if (existing.thumbnailFileId != ref.thumbnailFileId &&
              ref.thumbnailFileId != null) {
            existing.thumbnailFileId = ref.thumbnailFileId;
            updated = true;
          }
          if (updated) {
            await existing.save();
            AppLogger.d('Updated file: ${ref.name}', tag: 'SyncService');
          }
          continue;
        }

        final record = FileRecord(
          fileId: ref.fileId,
          name: ref.name,
          folderId: ref.folderId,
          metadataMessageId: ref.metadataMessageId ?? 0,
          metadataFileId: ref.metaFileId,
          sizeMb: ref.sizeMb ?? 0.0,
          mimeType: ref.mimeType ?? 'application/octet-stream',
          uploadedAt: ref.uploadedAt != null
              ? DateTime.tryParse(ref.uploadedAt!) ?? DateTime.now()
              : DateTime.now(),
          chunkCount: ref.chunkCount ?? 1,
          sha256Hash: ref.sha256 ?? '',
          thumbnailFileId: ref.thumbnailFileId,
        );
        await _hive.saveFile(record);
        added++;
        AppLogger.d('Synced: ${ref.name}', tag: 'SyncService');
      }

      // ── Files: remove stale ───────────────────────────────────────────────
      onProgress?.call(0.9, 'Cleaning up stale entries...');
      final telegramFileIds = fileRefs.map((r) => r.fileId).toSet();
      final localFiles = _hive.allFiles;
      for (final local in localFiles) {
        if (!telegramFileIds.contains(local.fileId)) {
          if (pendingProtectedFileIds.contains(local.fileId) ||
              pendingDeletedFileIds.contains(local.fileId)) {
            AppLogger.d('Preserving local optimistic file: ${local.name}',
                tag: 'SyncService');
            continue;
          }
          if (DateTime.now().difference(local.uploadedAt).inMinutes < 15) {
            AppLogger.d(
                'Preserving recently uploaded local file: ${local.name}',
                tag: 'SyncService');
            continue;
          }
          await _hive.deleteFile(local.fileId);
          removed++;
          AppLogger.d('Removed stale file: ${local.name}', tag: 'SyncService');
        }
      }

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
}

class SyncResult {
  final int added;
  final int removed;
  SyncResult({required this.added, required this.removed});
  bool get hasChanges => added > 0 || removed > 0;
}
