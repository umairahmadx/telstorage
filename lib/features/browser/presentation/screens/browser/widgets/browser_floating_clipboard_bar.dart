/*
 * File: browser_floating_clipboard_bar.dart
 * Description: Floating action overlay card showing pending cut/copy items and paste triggers without shifting screen content.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import '../viewmodel/browser_view_model.dart';

/// Floating clipboard overlay card displaying active cut/copy operations.
class BrowserFloatingClipboardBar extends StatelessWidget {
  /// Associated browser state.
  final BrowserState state;

  /// Callback when Cancel is tapped.
  final VoidCallback onCancel;

  /// Callback when Paste Here is tapped.
  final VoidCallback onPaste;

  /// Constructs BrowserFloatingClipboardBar.
  const BrowserFloatingClipboardBar({
    super.key,
    required this.state,
    required this.onCancel,
    required this.onPaste,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final count =
        state.clipboardFileIds.length + state.clipboardFolderIds.length;
    final isMove = state.clipboardMode == ClipboardMode.move;

    return Material(
      color: colors.bgSurface,
      borderRadius: BorderRadius.circular(20),
      elevation: 10,
      shadowColor: AppColors.black.withValues(alpha: 0.5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.borderSubtle, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colors.textPrimary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isMove
                    ? Icons.drive_file_move_rounded
                    : Icons.content_copy_rounded,
                size: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count ${count == 1 ? "item" : "items"} selected',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isMove ? 'Ready to move' : 'Ready to copy',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: colors.textSecondary,
              ),
              child: const Text('Cancel', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 4),
            ElevatedButton.icon(
              onPressed: onPaste,
              icon: const Icon(Icons.paste_rounded, size: 16),
              label: const Text(
                'Paste Here',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                backgroundColor: colors.accentPrimary,
                foregroundColor: colors.bgPrimary,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
