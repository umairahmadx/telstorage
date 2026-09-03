/*
 * File: app_file_grid_tile.dart
 * Description: Grid item card for file display with media thumbnail, status badges, and curved foreground ripple feedback.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/thumbnail_widget.dart';

/// Unified file card for grid view layouts with curved foreground ink ripple.
class AppFileGridTile extends StatelessWidget {
  /// Associated FileRecord data model.
  final FileRecord file;

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

  /// Constructs AppFileGridTile.
  const AppFileGridTile({
    super.key,
    required this.file,
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
              // Preview / Thumbnail Area
              Expanded(
                child: Stack(
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: ThumbnailWidget(
                          file: file,
                          width: double.infinity,
                          height: double.infinity,
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
                                  AppIcons.check,
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

              // File Name and Options Trigger
              Row(
                children: [
                  Expanded(
                    child: Text(
                      file.name,
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
                            AppIcons.moreVert,
                            color: colors.textSecondary,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),

              // File Size
              Text(
                file.formattedSize,
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
