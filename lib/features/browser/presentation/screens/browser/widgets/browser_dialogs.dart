/// File: browser_dialogs.dart
/// Description: Extracted dialog and modal bottom sheet helpers for the Browser screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/downloads/presentation/screens/downloads/viewmodel/downloads_view_model.dart';
import 'package:telstorage/shared/widgets/file_detail_sheet.dart';
import 'package:telstorage/shared/widgets/share_link_sheet.dart';
import '../viewmodel/browser_view_model.dart';
import 'browser_sort_sheet.dart';

/// Static utility class containing modal dialogs and bottom sheets for the Browser screen.
abstract final class BrowserDialogs {
  /// Displays the file detail modal bottom sheet with actions.
  static void showFileDetail(BuildContext context, FileRecord file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FileDetailSheet(
        file: file,
        onShare: () {
          Navigator.pop(ctx);
          showShareSheet(context, file);
        },
        onDownload: () {
          Navigator.pop(ctx);
          context.read<BrowserBloc>().add(EnqueueDownload(file));
        },
        onRename: () {
          Navigator.pop(ctx);
          renameFile(context, file);
        },
        onMove: () {
          Navigator.pop(ctx);
          context.read<BrowserBloc>().add(SetClipboard(
                mode: ClipboardMode.move,
                fileIds: {file.fileId},
                folderIds: {},
                sourceFolderId: file.folderId,
              ));
        },
        onCopy: () {
          Navigator.pop(ctx);
          context.read<BrowserBloc>().add(SetClipboard(
                mode: ClipboardMode.copy,
                fileIds: {file.fileId},
                folderIds: {},
                sourceFolderId: file.folderId,
              ));
        },
        onDelete: () {
          Navigator.pop(ctx);
          deleteFile(context, file);
        },
      ),
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
    final ctrl = TextEditingController(text: file.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Rename File'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (result != null && result.trim().isNotEmpty) {
      context.read<BrowserBloc>().add(RenameFile(file.fileId, result.trim()));
    }
  }

  /// Displays the file deletion confirmation dialog.
  static Future<void> deleteFile(BuildContext context, FileRecord file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Delete "${file.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (ok == true) {
      context.read<BrowserBloc>().add(DeleteFile(file.fileId));
    }
  }

  /// Displays the folder actions modal bottom sheet.
  static void showFolderDetail(BuildContext context, FolderRecord folder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                renameFolder(context, folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move'),
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
              leading: const Icon(Icons.content_copy_rounded),
              title: const Text('Copy'),
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
              leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.error),
              title: const Text('Delete', style: TextStyle(color: AppTheme.error)),
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
    final ctrl = TextEditingController(text: folder.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Rename Folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (result != null && result.trim().isNotEmpty) {
      context.read<BrowserBloc>().add(RenameFolder(folder.id, result.trim()));
    }
  }

  /// Displays the folder deletion confirmation dialog.
  static Future<void> deleteFolder(BuildContext context, FolderRecord folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Delete "${folder.name}"?'),
        content: const Text(
            'All contents inside this folder will also be deleted. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => BrowserSortSheet(
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
