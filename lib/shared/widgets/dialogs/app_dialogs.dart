/*
 * File: app_dialogs.dart
 * Description: Centralized modal dialog and sheet helper exposing confirmation, text input, and unified About File modals.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/dialogs/file_detail_sheet.dart';

/// Centralized modal dialog controller for TelStorage.
abstract final class AppDialogs {
  /// Shows a standardized confirmation dialog.
  static Future<bool?> showConfirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDestructive = false,
  }) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(message, style: TextStyle(color: colors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelText, style: TextStyle(color: colors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: isDestructive ? colors.error : colors.accentPrimary,
              foregroundColor: isDestructive ? colors.textPrimary : colors.bgPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(confirmText, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Shows a standardized text input dialog.
  static Future<String?> showInput(
    BuildContext context, {
    required String title,
    String? hintText,
    String? initialValue,
    String confirmText = 'Save',
    String cancelText = 'Cancel',
  }) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final controller = TextEditingController(text: initialValue);

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: colors.textTertiary),
            filled: true,
            fillColor: colors.bgSurfaceInset,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colors.borderSubtle),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(cancelText, style: TextStyle(color: colors.textSecondary)),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(ctx, text);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: colors.accentPrimary,
              foregroundColor: colors.bgPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(confirmText, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Displays the unified 'About File' modal bottom sheet across all screens.
  static void showFileDetail(
    BuildContext context, {
    required FileRecord file,
    required VoidCallback onShare,
    required VoidCallback onDownload,
    required VoidCallback onRename,
    VoidCallback? onMove,
    VoidCallback? onCopy,
    required VoidCallback onDelete,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FileDetailSheet(
        file: file,
        onShare: onShare,
        onDownload: onDownload,
        onRename: onRename,
        onMove: onMove,
        onCopy: onCopy,
        onDelete: onDelete,
      ),
    );
  }
}
