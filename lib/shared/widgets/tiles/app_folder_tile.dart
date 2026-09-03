/*
 * File: app_folder_tile.dart
 * Description: Centralized folder list tile component displaying folder icon, name, item count, selection checkbox, and action trigger.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';

/// Centralized folder item tile reused across directory navigation in TelStorage.
class AppFolderTile extends StatelessWidget {
  /// Associated FolderRecord entity.
  final FolderRecord folder;

  /// Number of items contained in this folder.
  final int itemCount;

  /// Whether this folder is selected in multi-selection mode.
  final bool isSelected;

  /// Whether multi-selection mode is active.
  final bool isSelectionMode;

  /// Optional custom directional border radius.
  final BorderRadiusGeometry? borderRadius;

  /// Primary tap callback.
  final VoidCallback? onTap;

  /// Long press callback.
  final VoidCallback? onLongPress;

  /// Callback when more options button is tapped.
  final VoidCallback? onActionTap;

  /// Constructs AppFolderTile.
  const AppFolderTile({
    super.key,
    required this.folder,
    this.itemCount = 0,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.borderRadius,
    this.onTap,
    this.onLongPress,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSurfaceCard(
        onTap: onTap != null
            ? () {
                HapticFeedback.lightImpact();
                onTap!();
              }
            : null,
        onLongPress: onLongPress,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        color: isSelected
            ? colors.accentPrimary.withValues(alpha: 0.08)
            : colors.bgSurface,
        borderColor: isSelected
            ? colors.accentPrimary.withValues(alpha: 0.4)
            : colors.borderSubtle,
        child: Row(
          children: [
            if (isSelectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color:
                        isSelected ? colors.accentPrimary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? colors.accentPrimary
                          : colors.textTertiary,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Icon(AppIcons.check, size: 14, color: colors.bgPrimary)
                      : null,
                ),
              ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.fileFolder.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(AppIcons.folder,
                  color: colors.fileFolder, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
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
            if (onActionTap != null)
              IconButton(
                icon: Icon(AppIcons.moreVert,
                    color: colors.textSecondary, size: 20),
                onPressed: onActionTap,
              ),
          ],
        ),
      ),
    );
  }
}
