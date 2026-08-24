/// File: browser_file_grid_tile.dart
/// Description: Grid tile component displaying file thumbnail, name, and size.
library;

import 'package:flutter/material.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/thumbnail_widget.dart';

/// Grid item card rendering an individual file with selection checkbox.
class BrowserFileGridTile extends StatelessWidget {
  /// FileRecord entity.
  final FileRecord file;

  /// Whether this file is currently selected.
  final bool isSelected;

  /// Whether the browser is in multi-selection mode.
  final bool isMultiSelect;

  /// Primary tap callback.
  final VoidCallback onTap;

  /// Long press callback for selection.
  final VoidCallback onLongPress;

  /// Callback when more options button is tapped.
  final VoidCallback onMore;

  /// Constructs BrowserFileGridTile.
  const BrowserFileGridTile({
    super.key,
    required this.file,
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? colors.accentPrimary.withValues(alpha: 0.15)
              : colors.bgSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? colors.accentPrimary : colors.borderSubtle,
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Center(child: _buildPreview(colors)),
                  if (isMultiSelect)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected
                            ? colors.accentPrimary
                            : colors.textTertiary,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    file.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: onMore,
                  child: Icon(Icons.more_vert_rounded,
                      color: colors.textSecondary, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              file.formattedSize,
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds preview thumbnail or generic document icon.
  Widget _buildPreview(AppColorsExtension colors) {
    if (file.thumbnailFileId != null ||
        file.isImage ||
        file.isVideo ||
        file.isPdf) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ThumbnailWidget(
          file: file,
          width: double.infinity,
          height: double.infinity,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.accentPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.insert_drive_file_outlined,
        color: colors.accentPrimary,
        size: 32,
      ),
    );
  }
}
