/*
 * File: app_batch_action_bar.dart
 * Description: Centralized bottom floating batch action bar displayed during multi-selection mode with Select All, download, and file operation actions.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_theme.dart';

/// Centralized floating action bar for batch operations on selected files and folders.
class AppBatchActionBar extends StatelessWidget {
  /// Number of currently selected items.
  final int selectedCount;

  /// Whether all visible items are selected.
  final bool isAllSelected;

  /// Callback to dismiss selection mode.
  final VoidCallback onClearSelection;

  /// Callback to toggle select all / deselect all.
  final VoidCallback? onToggleSelectAll;

  /// Callback to batch delete selected items.
  final VoidCallback? onDelete;

  /// Callback to batch move selected items.
  final VoidCallback? onMove;

  /// Callback to batch copy selected items.
  final VoidCallback? onCopy;

  /// Callback to batch download selected items.
  final VoidCallback? onDownload;

  /// Callback to batch share selected items.
  final VoidCallback? onShare;

  /// Constructs AppBatchActionBar.
  const AppBatchActionBar({
    super.key,
    required this.selectedCount,
    this.isAllSelected = false,
    required this.onClearSelection,
    this.onToggleSelectAll,
    this.onDelete,
    this.onMove,
    this.onCopy,
    this.onDownload,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.textPrimary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: onClearSelection,
              tooltip: 'Cancel selection',
            ),
            if (onToggleSelectAll != null)
              IconButton(
                icon: Icon(
                  isAllSelected
                      ? Icons.deselect_rounded
                      : Icons.select_all_rounded,
                ),
                tooltip: isAllSelected ? 'Deselect all' : 'Select all',
                onPressed: onToggleSelectAll,
              ),
            const SizedBox(width: 4),
            Text(
              '$selectedCount selected',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            if (onDownload != null)
              IconButton(
                icon: const Icon(Icons.download_rounded),
                tooltip: 'Download selected',
                onPressed: onDownload,
              ),
            if (onShare != null)
              IconButton(
                icon: const Icon(Icons.share_rounded),
                tooltip: 'Share selected',
                onPressed: onShare,
              ),
            if (onCopy != null)
              IconButton(
                icon: const Icon(Icons.content_copy_rounded),
                tooltip: 'Copy selected',
                onPressed: onCopy,
              ),
            if (onMove != null)
              IconButton(
                icon: const Icon(Icons.drive_file_move_rounded),
                tooltip: 'Move selected',
                onPressed: onMove,
              ),
            if (onDelete != null)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, color: colors.error),
                tooltip: 'Delete selected',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
