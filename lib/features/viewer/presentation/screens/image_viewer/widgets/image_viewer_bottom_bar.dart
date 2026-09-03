/*
 * File: image_viewer_bottom_bar.dart
 * Description: Bottom overlay bar for image viewer displaying file size, upload date, and save-to-device trigger with animated visibility.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';

/// Animated bottom info and action bar for fullscreen image viewer.
class ImageViewerBottomBar extends StatelessWidget {
  /// Associated FileRecord data model.
  final FileRecord file;

  /// Whether bottom bar is currently visible in immersive mode.
  final bool isVisible;

  /// Whether this file is currently saved on the device.
  final bool isSaved;

  /// Whether a save action is currently processing.
  final bool isSaving;

  /// Callback to save image to device.
  final VoidCallback onSave;

  /// Callback to share image directly.
  final VoidCallback onShare;

  /// Constructs ImageViewerBottomBar.
  const ImageViewerBottomBar({
    super.key,
    required this.file,
    required this.isVisible,
    this.isSaved = false,
    this.isSaving = false,
    required this.onSave,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(file.uploadedAt);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      bottom: isVisible ? 0 : -100,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 12,
          top: 16,
          left: 20,
          right: 20,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              colors.bgPrimary.withValues(alpha: 0.85),
              colors.bgPrimary.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.formattedSize,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: colors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Download action icon button
                Container(
                  width: 44,
                  height: 44,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: isSaved
                        ? colors.success.withValues(alpha: 0.18)
                        : colors.bgSurface.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSaved
                          ? colors.success.withValues(alpha: 0.4)
                          : colors.borderSubtle.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isSaving ? null : onSave,
                      customBorder: const CircleBorder(),
                      child: Center(
                        child: isSaving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.accentPrimary,
                                ),
                              )
                            : Icon(
                                isSaved
                                    ? AppIcons.statusDone
                                    : AppIcons.download,
                                size: 20,
                                color: isSaved
                                    ? colors.success
                                    : colors.textPrimary,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Share action icon button
                Container(
                  width: 44,
                  height: 44,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: colors.bgSurface.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.borderSubtle.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onShare,
                      customBorder: const CircleBorder(),
                      child: Center(
                        child: Icon(
                          AppIcons.share,
                          size: 20,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
