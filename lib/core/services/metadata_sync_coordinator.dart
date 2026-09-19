/*
 * File: metadata_sync_coordinator.dart
 * Description: Debounced coordinator for metadata partition syncs and pinned catalog updates to prevent rapid sequential Telegram API calls and 429 rate limits.
 */

import 'dart:async';
import '../constants/app_constants.dart';
import '../models/app_metadata.dart';
import '../utils/app_logger.dart';
import 'metadata_partition_service.dart';
import 'metadata_service.dart';

/// Models a pending file removal mutation in the debounce queue.
class _PendingRemoval {
  final String fileId;
  final double sizeMb;
  final String mimeType;
  final String? folderId;

  const _PendingRemoval({
    required this.fileId,
    required this.sizeMb,
    required this.mimeType,
    this.folderId,
  });
}

/// Models a pending file reference update (rename/move) in the debounce queue.
class _PendingUpdate {
  final FileRef ref;
  final String? oldFolderId;
  final bool folderChanged;

  const _PendingUpdate({
    required this.ref,
    this.oldFolderId,
    this.folderChanged = false,
  });
}

/// Debounces and coalesces partition sync and pinned metadata updates to Telegram.
///
/// Prevents repetitive, sequential HTTP requests when files are uploaded, moved,
/// or deleted in rapid succession, thereby preventing Telegram 429 flood waits.
class MetadataSyncCoordinator {
  final MetadataService _metadataService;
  final MetadataPartitionService _partitionService;
  final Duration debounceDuration;

  final Map<String, Map<String, dynamic>> _pendingAdditions = {};
  final Map<String, _PendingRemoval> _pendingRemovals = {};
  final Map<String, _PendingUpdate> _pendingUpdates = {};

  Timer? _debounceTimer;
  Future<void>? _activeFlush;

  MetadataSyncCoordinator(
    this._metadataService,
    this._partitionService, {
    this.debounceDuration = const Duration(milliseconds: 1500),
  });

  /// Whether any metadata or partition mutations are pending flush.
  bool get hasPending =>
      _pendingAdditions.isNotEmpty ||
      _pendingRemovals.isNotEmpty ||
      _pendingUpdates.isNotEmpty;

  /// Total count of pending mutations across additions, removals, and updates.
  int get pendingCount =>
      _pendingAdditions.length +
      _pendingRemovals.length +
      _pendingUpdates.length;

  /// Enqueues a newly uploaded file record for debounced metadata and partition commit.
  void enqueueAddFile(
    Map<String, dynamic> fileData, {
    bool debounce = true,
  }) {
    final fileId = fileData['file_id'] as String;
    // If it was marked for removal previously, cancel out removal
    _pendingRemovals.remove(fileId);
    _pendingAdditions[fileId] = Map<String, dynamic>.from(fileData);

    if (debounce) {
      _scheduleDebounce();
    }
  }

  /// Enqueues a file removal for debounced metadata and partition commit.
  void enqueueRemoveFile(
    String fileId,
    double sizeMb,
    String mimeType, {
    String? folderId,
    bool debounce = true,
  }) {
    // If it was pending addition in the same burst, remove without remote roundtrip
    if (_pendingAdditions.remove(fileId) != null) {
      _pendingUpdates.remove(fileId);
      return;
    }

    _pendingUpdates.remove(fileId);
    _pendingRemovals[fileId] = _PendingRemoval(
      fileId: fileId,
      sizeMb: sizeMb,
      mimeType: mimeType,
      folderId: folderId,
    );

    if (debounce) {
      _scheduleDebounce();
    }
  }

  /// Enqueues a file reference update (rename/move) for debounced commit.
  void enqueueUpdateFileRef(
    FileRef ref, {
    String? oldFolderId,
    bool folderChanged = false,
    bool debounce = true,
  }) {
    _pendingUpdates[ref.fileId] = _PendingUpdate(
      ref: ref,
      oldFolderId: oldFolderId,
      folderChanged: folderChanged,
    );

    if (debounce) {
      _scheduleDebounce();
    }
  }

  void _scheduleDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      flush().catchError((e) {
        AppLogger.w('Debounced metadata flush failed: $e',
            tag: 'MetadataSyncCoordinator');
      });
    });
  }

  /// Flushes all pending additions, removals, and updates immediately in a coalesced batch.
  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    if (!hasPending) return;

    final previousFlush = _activeFlush;
    final completer = Completer<void>();
    _activeFlush = completer.future;

    if (previousFlush != null) {
      await previousFlush.catchError((_) {});
    }

    try {
      if (!hasPending) return;

      // Extract snapshots of pending changes
      final additions = List<Map<String, dynamic>>.from(_pendingAdditions.values);
      final removals = List<_PendingRemoval>.from(_pendingRemovals.values);
      final updates = List<_PendingUpdate>.from(_pendingUpdates.values);

      _pendingAdditions.clear();
      _pendingRemovals.clear();
      _pendingUpdates.clear();

      AppLogger.d(
        'Flushing coalesced metadata: ${additions.length} additions, '
        '${removals.length} removals, ${updates.length} updates',
        tag: 'MetadataSyncCoordinator',
      );

      final latestMeta = await _metadataService.fetch();
      final affectedFolders = <String>{};

      // 1. Process Removals
      for (final rem in removals) {
        latestMeta.totalFiles = (latestMeta.totalFiles - 1).clamp(0, 999999);
        latestMeta.storageUsedMb =
            (latestMeta.storageUsedMb - rem.sizeMb).clamp(0.0, double.infinity);
        latestMeta.recentFiles.removeWhere((f) => f.fileId == rem.fileId);

        final cat = _category(rem.mimeType);
        final catStat = latestMeta.categories[cat];
        if (catStat != null) {
          catStat.count = (catStat.count - 1).clamp(0, 999999);
          catStat.sizeMb =
              (catStat.sizeMb - rem.sizeMb).clamp(0.0, double.infinity);
        }

        final folderKey = rem.folderId ?? AppConstants.rootFolderPartitionId;
        affectedFolders.add(folderKey);
        await _partitionService.removeFileRefFromPartition(
          latestMeta,
          folderKey,
          rem.fileId,
        );

        if (rem.folderId != null) {
          for (final f in latestMeta.folders) {
            if (f.id == rem.folderId && f.itemCount > 0) f.itemCount--;
          }
        }
      }

      // 2. Process Updates (Moves / Renames)
      for (final upd in updates) {
        final newFolderId = upd.ref.folderId ?? AppConstants.rootFolderPartitionId;
        final prevFolderId = upd.folderChanged
            ? (upd.oldFolderId ?? AppConstants.rootFolderPartitionId)
            : (upd.oldFolderId ?? upd.ref.folderId ?? AppConstants.rootFolderPartitionId);

        if (prevFolderId != newFolderId) {
          affectedFolders.add(prevFolderId);
          await _partitionService.removeFileRefFromPartition(
            latestMeta,
            prevFolderId,
            upd.ref.fileId,
          );
          for (final f in latestMeta.folders) {
            if (f.id == prevFolderId && f.itemCount > 0) f.itemCount--;
            if (f.id == newFolderId) f.itemCount++;
          }
        }

        affectedFolders.add(newFolderId);
        await _partitionService.saveFileRefsToPartition(
          latestMeta,
          newFolderId,
          [upd.ref],
        );

        final idx = latestMeta.recentFiles
            .indexWhere((f) => f.fileId == upd.ref.fileId);
        if (idx != -1) {
          latestMeta.recentFiles[idx] = upd.ref;
        }
      }

      // 3. Process Additions
      final Map<String, List<FileRef>> partitionBatch = {};
      for (final fileData in additions) {
        latestMeta.totalFiles++;
        latestMeta.storageUsedMb += (fileData['size_mb'] as num).toDouble();

        final mimeType = fileData['mime_type'] as String? ?? '';
        final cat = _category(mimeType);
        final catStat = latestMeta.categories.putIfAbsent(
          cat,
          () => CategoryStat(count: 0, sizeMb: 0.0),
        );
        catStat.count++;
        catStat.sizeMb += (fileData['size_mb'] as num).toDouble();

        final metaFileId = fileData['metadata_file_id'] as String?;
        if (metaFileId != null && metaFileId.isNotEmpty) {
          final ref = FileRef(
            fileId: fileData['file_id'] as String,
            metaFileId: metaFileId,
            name: fileData['name'] as String,
            folderId: fileData['folder_id'] as String?,
            sizeMb: (fileData['size_mb'] as num?)?.toDouble(),
            mimeType: fileData['mime_type'] as String?,
            uploadedAt: fileData['uploaded_at'] as String?,
            chunkCount: fileData['chunk_count'] as int?,
            sha256: fileData['sha256'] as String?,
            metadataMessageId: fileData['metadata_message_id'] as int?,
            thumbnailFileId: fileData['thumbnail_file_id'] as String?,
          );

          final fId = ref.folderId ?? AppConstants.rootFolderPartitionId;
          partitionBatch.putIfAbsent(fId, () => []).add(ref);
          if (ref.folderId != null) {
            for (final f in latestMeta.folders) {
              if (f.id == ref.folderId) f.itemCount++;
            }
          }

          latestMeta.recentFiles
              .removeWhere((f) => f.fileId == fileData['file_id']);
          latestMeta.recentFiles.insert(0, ref);
        }
      }

      if (partitionBatch.isNotEmpty) {
        for (final entry in partitionBatch.entries) {
          affectedFolders.add(entry.key);
          await _partitionService.saveFileRefsToPartition(
            latestMeta,
            entry.key,
            entry.value,
          );
        }
      }

      if (latestMeta.recentFiles.length > 20) {
        latestMeta.recentFiles = latestMeta.recentFiles.take(20).toList();
      }

      // 4. Update Global Metadata pinned index on Telegram (Single update!)
      await _metadataService.update(latestMeta);
      AppLogger.i(
        'Coalesced metadata committed successfully (${affectedFolders.length} partitions updated)',
        tag: 'MetadataSyncCoordinator',
      );
    } catch (e) {
      AppLogger.e('Failed to commit coalesced metadata: $e',
          tag: 'MetadataSyncCoordinator', error: e);
      rethrow;
    } finally {
      completer.complete();
    }
  }

  /// Cancels any scheduled debounce timer and clears pending in-memory mutations.
  void cancel() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingAdditions.clear();
    _pendingRemovals.clear();
    _pendingUpdates.clear();
  }

  /// Disposes the coordinator and releases all timers.
  void dispose() {
    cancel();
  }

  static String _category(String mimeType) {
    if (mimeType.startsWith('image/')) return 'images';
    if (mimeType.startsWith('video/')) return 'videos';
    if (mimeType.startsWith('audio/')) return 'audio';
    if (mimeType == 'application/pdf' ||
        mimeType.contains('word') ||
        mimeType.contains('document') ||
        mimeType.contains('text/')) {
      return 'documents';
    }
    return 'other';
  }
}
