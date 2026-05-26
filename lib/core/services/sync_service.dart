import 'dart:convert';
import '../models/file_record.dart';
import '../models/folder_record.dart';
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

    try {
      onProgress?.call(0.0, 'Connecting to Telegram...');
      print('🔄 [SyncService] Starting full sync from Telegram...');

      final appMeta = await _metadata.fetch();

      // ── Folders: add missing ──────────────────────────────────────────────
      onProgress?.call(0.05, 'Syncing folders...');
      print('🔄 [SyncService] ${appMeta.folders.length} folder(s) on Telegram');
      for (final folder in appMeta.folders) {
        if (_hive.getFolder(folder.id) == null) {
          await _hive.saveFolder(FolderRecord.fromFolder(folder));
          added++;
          print('➕ [SyncService] Added folder: ${folder.name}');
        }
      }

      // ── Folders: remove stale (deleted on another device) ─────────────────
      final telegramFolderIds =
          appMeta.folders.map((f) => f.id).toSet();
      final localFolders = _hive.allFolders;
      for (final local in localFolders) {
        if (!telegramFolderIds.contains(local.id)) {
          await _hive.deleteFolder(local.id);
          removed++;
          print('➖ [SyncService] Removed stale folder: ${local.name}');
        }
      }

      // ── Files: build index of what Telegram knows about ───────────────────
      final fileRefs = appMeta.files;
      print('🔄 [SyncService] ${fileRefs.length} file(s) on Telegram');

      // Add files that are on Telegram but not in local Hive
      for (var i = 0; i < fileRefs.length; i++) {
        final ref = fileRefs[i];
        onProgress?.call(
          0.1 + (i / fileRefs.length * 0.75),
          'Syncing ${i + 1}/${fileRefs.length}: ${ref.name}',
        );

        if (_hive.getFile(ref.fileId) != null) {
          print('⏭️  [SyncService] ${ref.name} already cached');
          continue;
        }

        try {
          print(
            '📥 [SyncService] Fetching index for ${ref.name} '
            '(meta file_id: ${ref.metaFileId})',
          );
          final bytes = await _telegram.downloadByFileId(ref.metaFileId);
          final fileMeta =
              jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          fileMeta['metadata_file_id'] = ref.metaFileId;
          await _hive.saveFile(FileRecord.fromMap(fileMeta));
          added++;
          print('✅ [SyncService] Synced: ${ref.name}');
        } catch (e) {
          print('⚠️  [SyncService] Could not sync ${ref.name}: $e');
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
          print('➖ [SyncService] Removed stale file: ${local.name}');
        }
      }

      onProgress?.call(1.0, 'Sync complete!');
      print(
        '✅ [SyncService] Done — +$added added, -$removed removed. '
        'Local: ${_hive.totalFiles} files, ${_hive.totalFolders} folders',
      );

      return SyncResult(added: added, removed: removed);
    } catch (e) {
      print('❌ [SyncService] Sync failed: $e');
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
