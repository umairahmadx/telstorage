/*
 * File: browser_dialogs.dart
 * Description: Modal dialog and sheet helpers for Browser screen delegating to centralized AppDialogs and AppSortFilterSheet.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
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
      onDownload: () {
        Navigator.pop(context);
        context.read<BrowserBloc>().add(EnqueueDownload(file));
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
              leading: Icon(Icons.drive_file_rename_outline_rounded, color: colors.textPrimary),
              title: Text('Rename', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                renameFolder(context, folder);
              },
            ),
            ListTile(
              leading: Icon(Icons.drive_file_move_outlined, color: colors.textPrimary),
              title: Text('Move', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
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
              leading: Icon(Icons.content_copy_rounded, color: colors.textPrimary),
              title: Text('Copy', style: TextStyle(color: colors.textPrimary)),
              onTap: () {
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
              leading: Icon(Icons.delete_outline_rounded, color: colors.error),
              title: Text('Delete', style: TextStyle(color: colors.error)),
              onTap: () {
                Navigator.pop(ctx);
                deleteFolder(context, folder);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Displays the folder rename dialog.
  static Future<void> renameFolder(BuildContext context, FolderRecord folder) async {
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
      items.add(
          '${stats.fileCount} ${stats.fileCount == 1 ? 'file' : 'files'}');
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
