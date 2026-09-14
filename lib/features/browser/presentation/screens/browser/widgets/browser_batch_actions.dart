/*
 * File: browser_batch_actions.dart
 * Description: Controller handling batch action confirmations and executions for multi-selected browser items.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/services/folder_traversal_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/widgets/browser_dialogs.dart';
import 'package:telstorage/shared/widgets/dialogs/app_dialogs.dart';

/// Controller coordinating confirmation dialogs and execution for browser batch actions.
abstract final class BrowserBatchActions {
  /// Displays a destructive confirmation dialog before executing a batch delete.
  static Future<void> handleBatchDelete(
    BuildContext context,
    BrowserState state,
  ) async {
    final folderCount = state.selectedFolderIds.length;
    final fileCount = state.selectedFileIds.length;
    final total = folderCount + fileCount;
    if (total == 0) return;

    final String title;
    final String message;

    if (folderCount > 0 && fileCount == 0) {
      final folderLabel = folderCount == 1 ? 'folder' : 'folders';
      title = 'Delete $folderCount $folderLabel?';
      message =
          'All contents inside the selected $folderLabel will be permanently deleted. This action cannot be undone.';
    } else if (fileCount > 0 && folderCount == 0) {
      final fileLabel = fileCount == 1 ? 'file' : 'files';
      title = 'Delete $fileCount $fileLabel?';
      message =
          'The selected $fileLabel will be permanently deleted. This action cannot be undone.';
    } else {
      final folderLabel = folderCount == 1 ? 'folder' : 'folders';
      final fileLabel = fileCount == 1 ? 'file' : 'files';
      title = 'Delete $total items?';
      message =
          'The selected $folderCount $folderLabel and $fileCount $fileLabel (and their contents) will be permanently deleted. This action cannot be undone.';
    }

    final confirmed = await AppDialogs.showConfirm(
      context,
      title: title,
      message: message,
      confirmText: 'Delete',
      isDestructive: true,
    );

    if (confirmed == true && context.mounted) {
      context.read<BrowserBloc>().add(BatchDelete());
    }
  }

  /// Displays download confirmation dialog and initiates batch download of selected items.
  static Future<void> handleBatchDownload(
    BuildContext context,
    BrowserState state,
  ) async {
    if (state.selectedFolderIds.isEmpty && state.selectedFileIds.isEmpty) return;

    if (!await Connectivity.hasConnection()) {
      if (!context.mounted) return;
      await AppDialogs.showInfo(
        context,
        title: 'Offline',
        message:
            'You are currently offline. Please check your internet connection to download files.',
      );
      return;
    }

    final repo = ServiceLocator.instance.storageRepository;
    final items = FolderTraversalService.resolveMultiSelection(
      folderIds: state.selectedFolderIds,
      fileIds: state.selectedFileIds,
      allFolders: repo.currentFolders,
      allFiles: repo.currentFiles,
    );
    final stats = FolderTraversalService.calculateStats(items);

    if (stats.totalFiles == 0) {
      if (!context.mounted) return;
      await AppDialogs.showInfo(
        context,
        title: 'No Files Selected',
        message: 'The selected item(s) contain no files to download.',
      );
      return;
    }

    if (!context.mounted) return;
    final ok = await BrowserDialogs.showBatchDownloadConfirmation(
      context,
      fileCount: stats.totalFiles,
      totalSizeMb: stats.totalSizeMb,
    );

    if (ok == true && context.mounted) {
      context.read<BrowserBloc>().add(BatchDownload(
            conflictResolver: (fileName) =>
                AppDialogs.showFileConflictDialog(context,
                    fileName: fileName, isBatch: true),
          ));
    }
  }
}
