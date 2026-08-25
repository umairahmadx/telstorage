/*
 * File: app_folder_grid_tile.dart
 * Description: Grid item card for folder display with icon, name, item count, selection mode, and curved foreground ripple feedback.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';

/// Centralized folder card for grid view layouts with curved foreground ink ripple.
class AppFolderGridTile extends StatelessWidget {
  /// Associated FolderRecord entity.
  final FolderRecord folder;

  /// Number of direct items contained in this folder.
  final int itemCount;

  /// Whether this card is currently selected.
  final bool isSelected;

  /// Whether the parent screen is in multi-selection mode.
  final bool isSelectionMode;

  /// Callback when tile is tapped.
  final VoidCallback onTap;

  /// Callback when tile is long pressed.
  final VoidCallback onLongPress;

  /// Callback when the secondary action/menu is tapped.
  final VoidCallback? onActionTap;

  /// Constructs AppFolderGridTile.
  const AppFolderGridTile({
    super.key,
    required this.folder,
    this.itemCount = 0,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.onTap,
    required this.onLongPress,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final borderRadius = BorderRadius.circular(20);

    return Material(
      color: isSelected
          ? colors.accentPrimary.withValues(alpha: 0.12)
          : colors.bgSurface,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: borderRadius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(
              color: isSelected ? colors.accentPrimary : colors.borderSubtle,
              width: isSelected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Folder Icon Area with selection badge
              Expanded(
                child: Stack(
                  children: [
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: colors.fileFolder.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.folder_rounded,
                          color: colors.fileFolder,
                          size: 32,
                        ),
                      ),
                    ),
                    if (isSelectionMode)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected
                                ? colors.accentPrimary
                                : colors.bgSurface.withValues(alpha: 0.8),
                            border: Border.all(
                              color: isSelected
                                  ? colors.accentPrimary
                                  : colors.borderSubtle,
                              width: 1.5,
                            ),
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: colors.bgPrimary,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Folder Name and Options Trigger
              Row(
                children: [
                  Expanded(
                    child: Text(
                      folder.name,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onActionTap != null)
                    Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: onActionTap,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.more_vert_rounded,
                            color: colors.textSecondary,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),

              // Item Count
              Text(
                '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
