/*
 * File: rename_file_dialog.dart
 * Description: Compact rename dialog widget where only the base name is editable and the file extension stays locked as a static suffix.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';

/// Compact modal dialog used by `AppDialogs.showRenameFile`.
///
/// Only [baseName] is editable; [extensionLabel] is rendered as a locked
/// suffix inside the same field container so the file type can never change.
/// The layout is tuned for small screens: 24dp insets, a single filled field
/// row, and a full-width Cancel/Rename button pair.
class RenameFileDialog extends StatefulWidget {
  /// Pre-filled editable portion of the file name.
  final String baseName;

  /// Locked extension including its dot (e.g. `.jpg`); empty when none.
  final String extensionLabel;

  /// Resolved dialog theme tokens.
  final AppColorsExtension colors;

  /// Label of the confirm button.
  final String confirmText;

  /// Label of the cancel button.
  final String cancelText;

  /// Constructs a [RenameFileDialog].
  const RenameFileDialog({
    super.key,
    required this.baseName,
    required this.extensionLabel,
    required this.colors,
    required this.confirmText,
    required this.cancelText,
  });

  @override
  State<RenameFileDialog> createState() => _RenameFileDialogState();
}

class _RenameFileDialogState extends State<RenameFileDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.baseName)
      ..addListener(_onTextChanged);
    // Place the cursor at the end of the pre-filled base name.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  /// Whether the trimmed base name is non-empty.
  bool get _canConfirm => _controller.text.trim().isNotEmpty;

  /// Closes the dialog returning the full new name (base + locked extension).
  void _confirm() {
    if (!_canConfirm) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(
      context,
      '${_controller.text.trim()}${widget.extensionLabel}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    return AlertDialog(
      backgroundColor: colors.bgSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(AppIcons.rename, color: colors.accentPrimary, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Rename File',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filled rounded-12 field holding the editable base name plus the
          // non-editable extension chip in a single row.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    style: TextStyle(color: colors.textPrimary),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _confirm(),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (widget.extensionLabel.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  // Locked extension: display-only, never editable.
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.bgSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.borderSubtle),
                      ),
                      child: Text(
                        widget.extensionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.extensionLabel.isEmpty
                ? 'Enter a name for this file.'
                : 'The ${widget.extensionLabel} extension stays fixed.',
            style: TextStyle(color: colors.textTertiary, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                    backgroundColor: colors.bgSurfaceInset,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(widget.cancelText),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _canConfirm ? _confirm : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accentPrimary,
                    foregroundColor: colors.bgPrimary,
                    disabledBackgroundColor: colors.bgSurfaceInset,
                    disabledForegroundColor: colors.textTertiary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    widget.confirmText,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}