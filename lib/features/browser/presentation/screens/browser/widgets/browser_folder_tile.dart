/// File: browser_folder_tile.dart
/// Description: List tile component rendering folder item with item count and actions.
library;

import 'package:flutter/material.dart';
import '../../../../../../core/models/folder_record.dart';
import '../../../../../../core/theme/app_theme.dart';

/// List item widget representing a folder in the browser view.
class BrowserFolderTile extends StatelessWidget {
  /// Associated FolderRecord data.
  final FolderRecord folder;

  /// Number of items contained in this folder.
  final int itemCount;

  /// Whether this folder is selected in multi-select mode.
  final bool isSelected;

  /// Whether multi-selection mode is active.
  final bool isMultiSelect;

  /// Primary tap callback.
  final VoidCallback onTap;

  /// Long press callback.
  final VoidCallback onLongPress;

  /// More options button callback.
  final VoidCallback onMore;

  /// Constructs BrowserFolderTile.
  const BrowserFolderTile({
    super.key,
    required this.folder,
    this.itemCount = 0,
    this.isSelected = false,
    this.isMultiSelect = false,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: isSelected
            ? colors.accentPrimary.withValues(alpha: 0.15)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (isMultiSelect)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected
                      ? colors.accentPrimary
                      : colors.textTertiary,
                ),
              ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.fileFolder.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.folder_rounded,
                  color: colors.fileFolder, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary),
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }
}
