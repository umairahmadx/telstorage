/*
 * File: browser_dialogs.dart
 * Description: Modal dialog and sheet helpers for Browser screen delegating to centralized AppDialogs and AppSortFilterSheet.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/models/file_record.dart';

import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/folder_traversal_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/features/downloads/presentation/screens/downloads/viewmodel/downloads_view_model.dart';
import 'package:telstorage/shared/widgets/dialogs/app_dialogs.dart';
import 'package:telstorage/shared/widgets/dialogs/app_sort_filter_sheet.dart';
import 'package:telstorage/shared/widgets/share_link_sheet.dart';
import '../viewmodel/browser_view_model.dart';

/// Static utility class containing modal dialogs and bottom sheets for the Browser screen.
abstract final class BrowserDialogs {
  /// Displays the file detail modal bottom sheet with actions.
  static void showFileDetail(BuildContext context, FileRecord file) {
    AppDialogs.showFileDetail(
      context,
      file: file,
      onShare: () {
        Navigator.pop(context);
        showShareSheet(context, file);
      },
      onDownload: () async {
        Navigator.pop(context);
        var policy = DownloadConflictPolicy.overwrite;
        if (!kIsWeb) {
          final hasConflict = await ServiceLocator.instance.downloadQueue
              .checkFileConflict(file);
          if (hasConflict && context.mounted) {
            final decision = await AppDialogs.showFileConflictDialog(
              context,
              fileName: file.name,
            );
            if (decision == null) return;
            if (decision.policy == DownloadConflictPolicy.skip) return;
            policy = decision.policy;
          }
        }
        if (context.mounted) {
          context
              .read<BrowserBloc>()
              .add(EnqueueDownload(file, policy: policy));
        }
      },
      onRename: () {
        Navigator.pop(context);
        renameFile(context, file);
      },
      onMove: () {
        Navigator.pop(context);
        context.read<BrowserBloc>().add(SetClipboard(
              mode: ClipboardMode.move,
              fileIds: {file.fileId},
              folderIds: {},
              sourceFolderId: file.folderId,
            ));
      },
      onCopy: () {
        Navigator.pop(context);
        context.read<BrowserBloc>().add(SetClipboard(
              mode: ClipboardMode.copy,
              fileIds: {file.fileId},
              folderIds: {},
              sourceFolderId: file.folderId,
            ));
      },
      onDelete: () {
        Navigator.pop(context);
        deleteFile(context, file);
      },
    );
  }

  /// Displays the web share link generator bottom sheet.
  static void showShareSheet(BuildContext context, FileRecord file) {
    final existing = context.read<TransferCubit>().getShareJob(file.fileId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: file,
        shareUrl: existing?.shareUrl,
        onCopyLink: (pwd, expiryDays, vanitySlug) async {
          context.read<BrowserBloc>().add(EnqueueShare(
                file,
                password: pwd,
                expiryDays: expiryDays,
                vanitySlug: vanitySlug,
              ));
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }

  /// Displays the file rename dialog.
  static Future<void> renameFile(BuildContext context, FileRecord file) async {
    final result = await AppDialogs.showInput(
      context,
      title: 'Rename File',
      initialValue: file.name,
      confirmText: 'Rename',
    );
    if (!context.mounted) return;
    if (result != null && result.trim().isNotEmpty) {
      context.read<BrowserBloc>().add(RenameFile(file.fileId, result.trim()));
    }
  }

  /// Displays the file deletion confirmation dialog.
  static Future<void> deleteFile(BuildContext context, FileRecord file) async {
    final ok = await AppDialogs.showConfirm(
      context,
      title: 'Delete "${file.name}"?',
      message: 'This action cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
    );
    if (!context.mounted) return;
    if (ok == true) {
      context.read<BrowserBloc>().add(DeleteFile(file.fileId));
    }
  }

  /// Displays the folder actions modal bottom sheet.
  static void showFolderDetail(BuildContext context, FolderRecord folder) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.download_rounded, color: colors.textPrimary),
              title: Text('Download Folder',
                  style: TextStyle(color: colors.textPrimary)),
              subtitle: Text('Download folder with all subfolders',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(ctx);
                downloadFolder(context, folder);
              },
            ),
            ListTile(
              leading: Icon(Icons.archive_outlined, color: colors.textPrimary),
              title: Text('Export as ZIP',
                  style: TextStyle(color: colors.textPrimary)),
              subtitle: Text('Compress folder into a .zip file',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(ctx);
                exportFolderAsZip(context, folder);
              },
            ),
            ListTile(
              leading: Icon(Icons.drive_file_rename_outline_rounded,
                  color: colors.textPrimary),
              title:
                  Text('Rename', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(ctx);
                renameFolder(context, folder);
              },
            ),
            ListTile(
              leading: Icon(Icons.drive_file_move_outlined,
                  color: colors.textPrimary),
              title: Text('Move', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(ctx);
                context.read<BrowserBloc>().add(SetClipboard(
                      mode: ClipboardMode.move,
                      fileIds: {},
                      folderIds: {folder.id},
                      sourceFolderId: folder.parentId,
                    ));
              },
            ),
            ListTile(
              leading:
                  Icon(Icons.content_copy_rounded, color: colors.textPrimary),
              title: Text('Copy', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(ctx);
                context.read<BrowserBloc>().add(SetClipboard(
                      mode: ClipboardMode.copy,
                      fileIds: {},
                      folderIds: {folder.id},
                      sourceFolderId: folder.parentId,
                    ));
              },
            ),
            ListTile(
              leading: Icon(Icons.share_outlined, color: colors.textPrimary),
              title: Text('Share Folder / Get Link',
                  style: TextStyle(color: colors.textPrimary)),
              subtitle: Text('Compress folder into ZIP and share public link',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.pop(ctx);
                shareFolder(context, folder);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: colors.error),
              title: Text('Delete', style: TextStyle(color: colors.error)),
              onTap: () {
                HapticFeedback.heavyImpact();
                Navigator.pop(ctx);
                deleteFolder(context, folder);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Displays the share link bottom sheet for [folder] packaged as a ZIP.
  static Future<void> shareFolder(
      BuildContext context, FolderRecord folder) async {
    try {
      await ServiceLocator.instance.syncService
          .ensureFolderTreeSynced(folder.id);
    } catch (e) {
      if (context.mounted) {
        final colors = Theme.of(context).extension<AppColorsExtension>()!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(e is OfflineException ? 'No internet connection' : '$e'),
            backgroundColor: colors.error,
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;
    final cleanName = FolderTraversalService.sanitizeSegment(folder.name);
    final repo = ServiceLocator.instance.storageRepository;
    final items = FolderTraversalService.resolveDescendants(
      targetFolderId: folder.id,
      allFolders: repo.currentFolders,
      allFiles: repo.currentFiles,
    );
    final stats = FolderTraversalService.calculateStats(items);

    final syntheticFile = FileRecord(
      fileId: folder.id,
      name: '$cleanName.zip',
      mimeType: 'application/zip',
      sizeMb: stats.totalSizeMb,
      metadataMessageId: 0,
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: '',
    );

    final existing =
        context.read<TransferCubit>().getShareJob(folder.id);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: syntheticFile,
        shareUrl: existing?.shareUrl,
        onCopyLink: (pwd, expiryDays, vanitySlug) async {
          context.read<BrowserBloc>().add(EnqueueShare(
                syntheticFile,
                password: pwd,
                expiryDays: expiryDays,
                vanitySlug: vanitySlug,
              ));
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }

  /// Displays the folder rename dialog.
  static Future<void> renameFolder(
      BuildContext context, FolderRecord folder) async {
    final result = await AppDialogs.showInput(
      context,
      title: 'Rename Folder',
      initialValue: folder.name,
      confirmText: 'Rename',
    );
    if (!context.mounted) return;
    if (result != null && result.trim().isNotEmpty) {
      context.read<BrowserBloc>().add(RenameFolder(folder.id, result.trim()));
    }
  }

  /// Displays the folder deletion confirmation dialog with full recursive stats.
  static Future<void> deleteFolder(
      BuildContext context, FolderRecord folder) async {
    final stats =
        ServiceLocator.instance.storageRepository.getFolderStats(folder.id);

    final details = StringBuffer();
    details.write('This folder contains ');
    final items = <String>[];
    if (stats.fileCount > 0) {
      items
          .add('${stats.fileCount} ${stats.fileCount == 1 ? 'file' : 'files'}');
    } else {
      items.add('0 files');
    }
    if (stats.subfolderCount > 0) {
      items.add(
          '${stats.subfolderCount} ${stats.subfolderCount == 1 ? 'subfolder' : 'subfolders'}');
    }
    details.write(items.join(' and '));
    details.write(' (${stats.formattedSize} storage).\n\n');
    details.write(
        'All contents inside this folder and its subfolders will be permanently deleted. This cannot be undone.');

    final ok = await AppDialogs.showConfirm(
      context,
      title: 'Delete "${folder.name}"?',
      message: details.toString(),
      confirmText: 'Delete',
      isDestructive: true,
    );
    if (!context.mounted) return;
    if (ok == true) {
      context.read<BrowserBloc>().add(DeleteFolder(folder.id));
    }
  }

  /// Initiates recursive folder download with confirmation.
  static Future<void> downloadFolder(
      BuildContext context, FolderRecord folder) async {
    if (!await Connectivity.hasConnection()) {
      if (!context.mounted) return;
      await AppDialogs.showInfo(
        context,
        title: 'Offline',
        message:
            'You are currently offline. Please check your internet connection to download folders.',
      );
      return;
    }

    final repo = ServiceLocator.instance.storageRepository;
    final items = FolderTraversalService.resolveDescendants(
      targetFolderId: folder.id,
      allFolders: repo.currentFolders,
      allFiles: repo.currentFiles,
    );
    final stats = FolderTraversalService.calculateStats(items);

    if (stats.totalFiles == 0) {
      if (!context.mounted) return;
      await AppDialogs.showInfo(
        context,
        title: 'Folder is Empty',
        message: '"${folder.name}" contains no files to download.',
      );
      return;
    }

    if (!context.mounted) return;
    final ok = await AppDialogs.showConfirm(
      context,
      title: 'Download "${folder.name}"?',
      message:
          'This will enqueue ${stats.totalFiles} ${stats.totalFiles == 1 ? 'file' : 'files'} (${stats.totalSizeMb.toStringAsFixed(1)} MB) preserving folder structure.',
      confirmText: 'Download',
    );
    if (!context.mounted) return;
    if (ok == true) {
      context.read<BrowserBloc>().add(DownloadFolder(
            folder,
            conflictResolver: (fileName) =>
                AppDialogs.showFileConflictDialog(context,
                    fileName: fileName, isBatch: true),
          ));
    }
  }

  /// Initiates folder export to ZIP archive with confirmation.
  static Future<void> exportFolderAsZip(
      BuildContext context, FolderRecord folder) async {
    if (!await Connectivity.hasConnection()) {
      if (!context.mounted) return;
      await AppDialogs.showInfo(
        context,
        title: 'Offline',
        message:
            'You are currently offline. Please check your internet connection to export archives.',
      );
      return;
    }

    final repo = ServiceLocator.instance.storageRepository;
    final items = FolderTraversalService.resolveDescendants(
      targetFolderId: folder.id,
      allFolders: repo.currentFolders,
      allFiles: repo.currentFiles,
    );
    final stats = FolderTraversalService.calculateStats(items);

    if (stats.totalFiles == 0) {
      if (!context.mounted) return;
      await AppDialogs.showInfo(
        context,
        title: 'Folder is Empty',
        message: '"${folder.name}" contains no files to export.',
      );
      return;
    }

    if (!context.mounted) return;
    final ok = await AppDialogs.showConfirm(
      context,
      title: 'Export "${folder.name}" as ZIP?',
      message:
          'This will download and compress ${stats.totalFiles} ${stats.totalFiles == 1 ? 'file' : 'files'} (${stats.totalSizeMb.toStringAsFixed(1)} MB) into "${folder.name}.zip".',
      confirmText: 'Export ZIP',
    );
    if (!context.mounted) return;
    if (ok == true) {
      context.read<BrowserBloc>().add(ExportFolderAsZip(folder));
    }
  }

  /// Displays batch download confirmation dialog.
  static Future<bool?> showBatchDownloadConfirmation(
    BuildContext context, {
    required int fileCount,
    required double totalSizeMb,
  }) {
    return AppDialogs.showConfirm(
      context,
      title: 'Download $fileCount ${fileCount == 1 ? 'file' : 'files'}?',
      message:
          'Are you sure you want to download all $fileCount items (${totalSizeMb.toStringAsFixed(1)} MB)?',
      confirmText: 'Download All',
    );
  }

  /// Opens the sort and grouping modal bottom sheet.
  static void showSortSheet(BuildContext context, BrowserState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AppSortFilterSheet(
        currentSort: state.sortOption,
        isAscending: state.sortAscending,
        currentGroup: state.groupOption,
        onSortChanged: (opt) =>
            context.read<BrowserBloc>().add(SortOptionChanged(opt)),
        onGroupChanged: (grp) =>
            context.read<BrowserBloc>().add(GroupOptionChanged(grp)),
      ),
    );
  }
}
