/*
 * File: app_file_tile.dart
 * Description: Centralized file list tile component displaying thumbnail preview, title, size, date, selection checkbox, and action triggers.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';
import 'package:telstorage/shared/widgets/thumbnail_widget.dart';

/// Centralized file list item widget reused across Home, Browser, and Downloads.
class AppFileTile extends StatelessWidget {
  /// File data model containing fileId, name, size, and metadata.
  final FileRecord file;

  /// Whether the parent screen is in multi-selection mode.
  final bool isSelectionMode;

  /// Whether this specific item is currently selected.
  final bool isSelected;

  /// Optional custom directional border radius.
  final BorderRadiusGeometry? borderRadius;

  /// Primary tap callback.
  final VoidCallback? onTap;

  /// Long press callback (typically enters multi-selection mode).
  final VoidCallback? onLongPress;

  /// Optional trailing widget override.
  final Widget? trailing;

  /// Optional custom subtitle text.
  final String? subtitleText;

  /// Callback when trailing menu or action button is tapped.
  final VoidCallback? onActionTap;

  /// Constructs AppFileTile.
  const AppFileTile({
    super.key,
    required this.file,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.borderRadius,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.subtitleText,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM, yyyy').format(file.uploadedAt);
    final subtitle = subtitleText ?? '${file.formattedSize} • $dateStr';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSurfaceCard(
        onTap: onTap,
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
            // Selection Checkbox or Leading Thumbnail
            if (isSelectionMode) ...[
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
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
            ],
            SizedBox(
              width: 44,
              height: 44,
              child: ThumbnailWidget(
                file: file,
                width: 44,
                height: 44,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
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
                    subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onActionTap != null)
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
