/*
 * File: video_player_top_bar.dart
 * Description: Glassmorphic top navigation bar for the video player displaying filename, index, size, back button, and download trigger.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Glassmorphic animated top bar overlay for video playback.
class VideoPlayerTopBar extends StatelessWidget {
  /// FileRecord being played.
  final FileRecord file;

  /// Index of currently selected video in folder.
  final int currentIndex;

  /// Total count of video files in folder.
  final int totalCount;

  /// Whether the bar is currently visible.
  final bool isVisible;

  /// Callback when navigating back.
  final VoidCallback onBack;

  /// Callback to save or download the video.
  final VoidCallback onSave;

  /// Constructs VideoPlayerTopBar.
  const VideoPlayerTopBar({
    super.key,
    required this.file,
    required this.currentIndex,
    required this.totalCount,
    required this.isVisible,
    required this.onBack,
    required this.onSave,
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
            Material(
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              shape: const CircleBorder(),
              child: IconButton(
                icon: Icon(AppIcons.back, color: colors.textPrimary, size: 22),
                onPressed: onBack,
                tooltip: 'Back',
              ),
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
                    '${currentIndex + 1} of $totalCount • ${file.formattedSize}',
                    style: TextStyle(
                      color: colors.textTertiary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              shape: const CircleBorder(),
              child: IconButton(
                icon: Icon(AppIcons.download, color: colors.textPrimary, size: 20),
                onPressed: onSave,
                tooltip: 'Save to Downloads',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
