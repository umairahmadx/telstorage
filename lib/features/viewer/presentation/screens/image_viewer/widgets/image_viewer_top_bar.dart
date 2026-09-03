/*
 * File: image_viewer_top_bar.dart
 * Description: Top navigation bar for image viewer displaying title, counter, back button, share, and more options with animated visibility.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';

/// Animated top action bar for fullscreen image viewer.
class ImageViewerTopBar extends StatelessWidget {
  /// Currently displayed file record.
  final FileRecord file;

  /// Zero-based index of current image in folder.
  final int currentIndex;

  /// Total count of viewable images in folder.
  final int totalCount;

  /// Whether top bar is currently visible in immersive mode.
  final bool isVisible;

  /// Callback when back button is pressed.
  final VoidCallback onBack;

  /// Callback when share button is pressed.
  final VoidCallback onShare;

  /// Callback when more options button is pressed.
  final VoidCallback onMore;

  /// Constructs ImageViewerTopBar.
  const ImageViewerTopBar({
    super.key,
    required this.file,
    required this.currentIndex,
    required this.totalCount,
    required this.isVisible,
    required this.onBack,
    required this.onShare,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      top: isVisible ? 0 : -100,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 8,
          bottom: 12,
          left: 12,
          right: 12,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.bgPrimary.withValues(alpha: 0.85),
              colors.bgPrimary.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(AppIcons.back, color: colors.textPrimary, size: 22),
              onPressed: onBack,
              tooltip: 'Back',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.name,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${currentIndex + 1} of $totalCount',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(AppIcons.share, color: colors.textPrimary, size: 20),
              onPressed: onShare,
              tooltip: 'Share image',
            ),
            IconButton(
              icon: Icon(AppIcons.moreVert, color: colors.textPrimary, size: 20),
              onPressed: onMore,
              tooltip: 'More options',
            ),
          ],
        ),
      ),
    );
  }
}
