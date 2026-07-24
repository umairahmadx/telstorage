import 'dart:convert';
import '../models/file_record.dart';
import '../models/folder_record.dart';
import '../models/app_metadata.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import 'hive_service.dart';
import 'metadata_service.dart';
import 'telegram_service.dart';

/// Keeps the local Hive cache in sync with Telegram's global metadata.
///
/// Called on every app startup. Performs a merge:
///   • Files in Telegram but not in Hive  → download meta + add to Hive
///   • Files in Hive but not in Telegram  → remove from Hive (deleted elsewhere)
///   • Folders follow the same logic
///
/// Always uses permanent file_ids — never calls getUpdates.
class SyncService {
  final MetadataService _metadata;
  final TelegramService _telegram;
  final HiveService _hive;

  SyncService(this._metadata, this._telegram, this._hive);

  /// Always call this on startup. Merges Telegram truth → local Hive.
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

      // ── Folders: add missing ──────────────────────────────────────────────
      onProgress?.call(0.05, 'Syncing folders...');
      AppLogger.d('${appMeta.folders.length} folder(s) on Telegram',
          tag: 'SyncService');
      for (final folder in appMeta.folders) {
        final local = _hive.getFolder(folder.id);
        if (local == null) {
          await _hive.saveFolder(FolderRecord.fromFolder(folder));
          added++;
          AppLogger.d('Added folder: ${folder.name}', tag: 'SyncService');
        } else if (local.name != folder.name ||
            local.parentId != folder.parentId) {
          local.name = folder.name;
          local.parentId = folder.parentId;
          await local.save();
          AppLogger.d('Updated folder: ${folder.name}', tag: 'SyncService');
        }
      }

      // ── Folders: remove stale (deleted on another device) ─────────────────
      final telegramFolderIds = appMeta.folders.map((f) => f.id).toSet();
      final localFolders = _hive.allFolders;
      for (final local in localFolders) {
        if (!telegramFolderIds.contains(local.id)) {
          await _hive.deleteFolder(local.id);
          removed++;
          AppLogger.d('Removed stale folder: ${local.name}',
              tag: 'SyncService');
        }
      }

      // ── Files: build index of what Telegram knows about ───────────────────
      final List<FileRef> fileRefs = [];
      if (appMeta.isPartitioned && appMeta.folderPartitionsMap.isNotEmpty) {
        for (final folderId in appMeta.folderPartitionsMap.keys) {
          final partition = await _metadata.fetchFolderPartition(folderId);
          if (partition != null) {
            fileRefs.addAll(partition.files);
          }
        }
      } else {
        fileRefs.addAll(appMeta.files);
      }
      AppLogger.d('${fileRefs.length} file(s) on Telegram', tag: 'SyncService');

      final List<FileRef> legacySyncQueue = [];

      // Add files that are on Telegram but not in local Hive
      for (var i = 0; i < fileRefs.length; i++) {
        final ref = fileRefs[i];
        onProgress?.call(
          0.1 + (i / fileRefs.length * 0.75),
          'Syncing ${i + 1}/${fileRefs.length}: ${ref.name}',
        );

        final existing = _hive.getFile(ref.fileId);
        if (existing != null) {
          // Update local record if name or folder changed on another device
          if (existing.name != ref.name || existing.folderId != ref.folderId) {
            existing.name = ref.name;
            existing.folderId = ref.folderId;
            await existing.save();
            AppLogger.d('Updated file: ${ref.name}', tag: 'SyncService');
          } else {
            AppLogger.d('${ref.name} already cached', tag: 'SyncService');
          }
          continue;
        }

        // Fast sync if metadata is stored inline in FileRef
        if (ref.sizeMb != null) {
          final record = FileRecord(
            fileId: ref.fileId,
            name: ref.name,
            folderId: ref.folderId,
            metadataMessageId: ref.metadataMessageId ?? 0,
            metadataFileId: ref.metaFileId,
            sizeMb: ref.sizeMb!,
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
          AppLogger.d('Fast-synced: ${ref.name}', tag: 'SyncService');
        } else {
          // Legacy sync fallback: create skeleton placeholder immediately
          final skeleton = FileRecord(
            fileId: ref.fileId,
            name: ref.name,
            folderId: ref.folderId,
            metadataMessageId: 0,
            metadataFileId: ref.metaFileId,
            sizeMb: 0.0,
            mimeType: 'application/octet-stream',
            uploadedAt: DateTime.now(),
            chunkCount: 1,
            sha256Hash: '',
          );
          await _hive.saveFile(skeleton);
          added++;
          legacySyncQueue.add(ref);
          AppLogger.d(
              'Created skeleton placeholder for legacy file: ${ref.name}',
              tag: 'SyncService');
        }
      }

      // ── Files: remove stale (deleted on another device) ───────────────────
      onProgress?.call(0.9, 'Cleaning up stale entries...');
      final telegramFileIds = fileRefs.map((r) => r.fileId).toSet();
      final localFiles = _hive.allFiles;
      for (final local in localFiles) {
        if (!telegramFileIds.contains(local.fileId)) {
          await _hive.deleteFile(local.fileId);
          removed++;
          AppLogger.d('Removed stale file: ${local.name}', tag: 'SyncService');
        }
      }

      if (legacySyncQueue.isNotEmpty) {
        // Fire-and-forget background legacy metadata fetching
        _backgroundSyncOldFiles(legacySyncQueue);
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

  Future<void> _backgroundSyncOldFiles(List<FileRef> legacyQueue) async {
    AppLogger.d(
        'Starting background sync of ${legacyQueue.length} legacy files...',
        tag: 'SyncService');
    final List<FileRef> migratedRefs = [];
    for (final ref in legacyQueue) {
      try {
        if (!await Connectivity.hasConnection()) {
          AppLogger.w('Background sync paused: no internet connection',
              tag: 'SyncService');
          break;
        }
        AppLogger.d('Background sync: fetching metadata for ${ref.name}',
            tag: 'SyncService');
        final bytes = await _telegram.downloadByFileId(ref.metaFileId);
        final fileMeta = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        fileMeta['metadata_file_id'] = ref.metaFileId;

        // Save locally to Hive
        await _hive.saveFile(FileRecord.fromMap(fileMeta));

        // Create updated FileRef object for global metadata migration
        migratedRefs.add(FileRef(
          fileId: ref.fileId,
          metaFileId: ref.metaFileId,
          name: ref.name,
          folderId: ref.folderId,
          sizeMb: (fileMeta['size_mb'] as num?)?.toDouble(),
          mimeType: fileMeta['mime_type'] as String?,
          uploadedAt: fileMeta['uploaded_at'] as String?,
          chunkCount: fileMeta['chunk_count'] as int?,
          sha256: fileMeta['sha256'] as String?,
          metadataMessageId: fileMeta['metadata_message_id'] as int?,
          thumbnailFileId: fileMeta['thumbnail_file_id'] as String?,
        ));

        AppLogger.d('Background sync completed for: ${ref.name}',
            tag: 'SyncService');
      } catch (e) {
        AppLogger.w('Background sync failed for ${ref.name}: $e',
            tag: 'SyncService');
      }
    }

    // Write updated metadata index back to Telegram so the migration is global/permanent
    if (migratedRefs.isNotEmpty) {
      try {
        AppLogger.d(
            'Updating global metadata index with ${migratedRefs.length} migrated references...',
            tag: 'SyncService');
        final appMeta = await _metadata.fetch();
        for (final migrated in migratedRefs) {
          appMeta.files.removeWhere((f) => f.fileId == migrated.fileId);
          appMeta.files.add(migrated);
        }
        await _metadata.update(appMeta);
        AppLogger.i(
            'Successfully saved upgraded global metadata index to Telegram.',
            tag: 'SyncService');
      } catch (e) {
        AppLogger.e('Failed to save upgraded metadata index to Telegram: $e',
            tag: 'SyncService');
      }
    }

    AppLogger.d('Background sync process complete.', tag: 'SyncService');
  }
}

class SyncResult {
  final int added;
  final int removed;
  SyncResult({required this.added, required this.removed});
  bool get hasChanges => added > 0 || removed > 0;
}
