/*
 * File: browser_batch_helper.dart
 * Description: Helper functions handling multi-select batch downloads, deletions, moves, copies, and ZIP archiving for the Browser ViewModel.
 */

import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/folder_traversal_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/zip_archive_service.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';
import 'package:telstorage/shared/widgets/dialogs/app_dialogs.dart';
import 'browser_event.dart';
import 'browser_state.dart';

/// Helper methods executing batch operations for BrowserBloc.
abstract final class BrowserBatchHelper {
  /// Computes selection sets when toggling select-all on visible items.
  static ({Set<String> folderIds, Set<String> fileIds}) toggleSelectAll({
    required BrowserState state,
    required bool selectAll,
  }) {
    final visibleFolderIds = state.folders.map((f) => f.id).toSet();
    final visibleFileIds = state.files.map((f) => f.fileId).toSet();

    if (selectAll) {
      return (
        folderIds: {...state.selectedFolderIds, ...visibleFolderIds},
        fileIds: {...state.selectedFileIds, ...visibleFileIds},
      );
    } else {
      final remainingFolderIds = Set<String>.from(state.selectedFolderIds)
        ..removeAll(visibleFolderIds);
      final remainingFileIds = Set<String>.from(state.selectedFileIds)
        ..removeAll(visibleFileIds);
      return (
        folderIds: remainingFolderIds,
        fileIds: remainingFileIds,
      );
    }
  }

  /// Enqueues all currently selected files and folders for download.
  static Future<int> executeBatchDownload({
    required BrowserState state,
    required StorageRepositoryContract repository,
    Future<FileConflictDecision?> Function(String fileName)? conflictResolver,
  }) async {
    if (state.selectedFolderIds.isEmpty && state.selectedFileIds.isEmpty) {
      return 0;
    }
    if (!await Connectivity.hasConnection()) {
      throw Exception('Cannot download while offline');
    }

    final allFolders = repository.currentFolders;
    final allFiles = repository.currentFiles;

    final items = FolderTraversalService.resolveMultiSelection(
      folderIds: state.selectedFolderIds,
      fileIds: state.selectedFileIds,
      allFolders: allFolders,
      allFiles: allFiles,
    );

    final downloadQueue = ServiceLocator.instance.downloadQueue;
    DownloadConflictPolicy? batchPolicy;
    var enqueuedCount = 0;

    for (final item in items) {
      var policy = batchPolicy ?? DownloadConflictPolicy.overwrite;
      final subpath = item.subpath.isNotEmpty ? item.subpath : null;

      if (batchPolicy == null && conflictResolver != null) {
        final hasConflict = await downloadQueue.checkFileConflict(
          item.file,
          subpath: subpath,
        );
        if (hasConflict) {
          final decision = await conflictResolver(item.file.name);
          if (decision == null) {
            // Cancel entire remaining batch
            break;
          }
          if (decision.applyToAll) {
            batchPolicy = decision.policy;
          }
          policy = decision.policy;
        }
      }

      if (policy == DownloadConflictPolicy.skip) {
        continue;
      }

      await downloadQueue.enqueueDownload(
        item.file,
        subpath: subpath,
        policy: policy,
      );
      enqueuedCount++;
    }

    return enqueuedCount;
  }

  /// Recursively enqueues an entire folder structure for download.
  static Future<int> executeDownloadFolder({
    required FolderRecord folder,
    required StorageRepositoryContract repository,
    Future<FileConflictDecision?> Function(String fileName)? conflictResolver,
  }) async {
    if (!await Connectivity.hasConnection()) {
      throw Exception('Cannot download folder while offline');
    }

    final allFolders = repository.currentFolders;
    final allFiles = repository.currentFiles;

    final items = FolderTraversalService.resolveDescendants(
      targetFolderId: folder.id,
      allFolders: allFolders,
      allFiles: allFiles,
    );

    final downloadQueue = ServiceLocator.instance.downloadQueue;
    DownloadConflictPolicy? batchPolicy;
    var enqueuedCount = 0;

    for (final item in items) {
      var policy = batchPolicy ?? DownloadConflictPolicy.overwrite;
      final subpath = item.subpath.isNotEmpty ? item.subpath : null;

      if (batchPolicy == null && conflictResolver != null) {
        final hasConflict = await downloadQueue.checkFileConflict(
          item.file,
          subpath: subpath,
        );
        if (hasConflict) {
          final decision = await conflictResolver(item.file.name);
          if (decision == null) {
            // Cancel entire remaining batch
            break;
          }
          if (decision.applyToAll) {
            batchPolicy = decision.policy;
          }
          policy = decision.policy;
        }
      }

      if (policy == DownloadConflictPolicy.skip) {
        continue;
      }

      await downloadQueue.enqueueDownload(
        item.file,
        subpath: subpath,
        policy: policy,
      );
      enqueuedCount++;
    }

    return enqueuedCount;
  }

  /// Exports a folder structure into a standalone `.zip` file in the background.
  static Future<String?> executeExportFolderAsZip({
    required FolderRecord folder,
    required StorageRepositoryContract repository,
  }) async {
    if (!await Connectivity.hasConnection()) {
      throw Exception('Cannot export ZIP while offline');
    }

    final allFolders = repository.currentFolders;
    final allFiles = repository.currentFiles;

    final items = FolderTraversalService.resolveDescendants(
      targetFolderId: folder.id,
      allFolders: allFolders,
      allFiles: allFiles,
    );

    return ZipArchiveService.exportFolderAsZip(
      folder: folder,
      items: items,
      downloadService: ServiceLocator.instance.downloadService,
    );
  }

  /// Batch deletes selected folders and files.
  static Future<void> executeBatchDelete({
    required Set<String> folderIds,
    required Set<String> fileIds,
    required StorageRepositoryContract repository,
  }) async {
    for (final folderId in List.from(folderIds)) {
      await repository.deleteFolder(folderId);
    }
    for (final fileId in List.from(fileIds)) {
      await repository.deleteFile(fileId);
    }
    ServiceLocator.instance.syncQueue.processQueue();
  }

  /// Batch moves selected folders and files into [targetFolderId].
  static Future<void> executeBatchMove({
    required Set<String> folderIds,
    required Set<String> fileIds,
    required String? targetFolderId,
    required StorageRepositoryContract repository,
  }) async {
    for (final folderId in List.from(folderIds)) {
      await repository.moveFolder(folderId, targetFolderId);
    }
    for (final fileId in List.from(fileIds)) {
      await repository.moveFile(fileId, targetFolderId);
    }
  }

  /// Batch copies selected folders and files into [targetFolderId].
  static Future<void> executeBatchCopy({
    required Set<String> folderIds,
    required Set<String> fileIds,
    required String? targetFolderId,
    required StorageRepositoryContract repository,
  }) async {
    for (final folderId in List.from(folderIds)) {
      await repository.copyFolder(folderId, targetFolderId);
    }
    for (final fileId in List.from(fileIds)) {
      await repository.copyFile(fileId, targetFolderId);
    }
  }

  /// Executes paste operation for clipboard content.
  static Future<void> executePasteClipboard({
    required ClipboardMode mode,
    required Set<String> folderIds,
    required Set<String> fileIds,
    required String? targetFolderId,
    required StorageRepositoryContract repository,
  }) async {
    if (mode == ClipboardMode.move) {
      await executeBatchMove(
        folderIds: folderIds,
        fileIds: fileIds,
        targetFolderId: targetFolderId,
        repository: repository,
      );
    } else if (mode == ClipboardMode.copy) {
      await executeBatchCopy(
        folderIds: folderIds,
        fileIds: fileIds,
        targetFolderId: targetFolderId,
        repository: repository,
      );
    }
  }
}
