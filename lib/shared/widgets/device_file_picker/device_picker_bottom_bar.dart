/*
 * File: device_picker_bottom_bar.dart
 * Description: Floating batch action bar presenting selection counters, select/clear toggles,
 * and primary submission button for device media and file pickers.
 */

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors_extension.dart';

/// Reusable bottom action bar for file and media picker sheets.
class DevicePickerBottomBar extends StatelessWidget {
  /// Number of items currently selected.
  final int selectedCount;

  /// Total size of selected items in bytes (optional, 0 if unknown).
  final int totalBytes;

  /// Whether all available items in the current view are selected.
  final bool isAllSelected;

  /// Callback to toggle select all / deselect all.
  final VoidCallback onToggleSelectAll;

  /// Callback when the user confirms upload.
  final VoidCallback onSubmit;

  /// Text label for the submit button (e.g. "Upload").
  final String submitLabel;

  /// Constructs DevicePickerBottomBar.
  const DevicePickerBottomBar({
    super.key,
    required this.selectedCount,
    this.totalBytes = 0,
    required this.isAllSelected,
    required this.onToggleSelectAll,
    required this.onSubmit,
    this.submitLabel = 'Upload',
  });

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return ' (${d.toStringAsFixed(1)} ${suffixes[i]})';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();
    final hasSelection = selectedCount > 0;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: colors?.bgSurface ?? Colors.black,
        border: Border(
          top: BorderSide(
            color: colors?.borderSubtle ?? Colors.white10,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Selection counter text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasSelection
                      ? '$selectedCount selected${_formatBytes(totalBytes)}'
                      : 'None selected',
                  style: TextStyle(
                    color: hasSelection
                        ? (colors?.textPrimary ?? Colors.white)
                        : (colors?.textSecondary ?? Colors.white54),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                GestureDetector(
                  onTap: onToggleSelectAll,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      isAllSelected ? 'Deselect All' : 'Select All',
                      style: TextStyle(
                        color: colors?.accentPrimary ?? Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Primary submission button
          FilledButton(
            onPressed: hasSelection ? onSubmit : null,
            style: FilledButton.styleFrom(
              backgroundColor: colors?.accentPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: colors?.bgSurfaceInset,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: Text(
              submitLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
