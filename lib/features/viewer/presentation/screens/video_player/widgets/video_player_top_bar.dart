/*
 * File: video_player_top_bar.dart
 * Description: Glassmorphic top navigation bar for the video player displaying filename, index, size, back button, rotate, share, download, and more options.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  /// Callback to toggle device orientation.
  final VoidCallback? onRotate;

  /// Current playback rate.
  final double playbackSpeed;

  /// Callback when speed button is pressed.
  final VoidCallback? onSpeed;

  /// Callback when audio tracks button is pressed.
  final VoidCallback? onAudioTracks;

  /// Callback when subtitles button is pressed.
  final VoidCallback? onSubtitles;

  /// Callback when share button is pressed.
  final VoidCallback onShare;

  /// Callback when more options button is pressed.
  final VoidCallback onMore;

  /// Constructs VideoPlayerTopBar.
  const VideoPlayerTopBar({
    super.key,
    required this.file,
    required this.currentIndex,
    required this.totalCount,
    required this.isVisible,
    required this.onBack,
    required this.onSave,
    this.onRotate,
    this.playbackSpeed = 1.0,
    this.onSpeed,
    this.onAudioTracks,
    this.onSubtitles,
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
                    '${file.formattedSize} • ${DateFormat('dd MMM yyyy, HH:mm').format(file.uploadedAt)}',
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
            if (onSpeed != null)
              Material(
                color: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                child: InkWell(
                  onTap: onSpeed,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      '${playbackSpeed == 1.0 ? '1.0' : playbackSpeed.toString()}x',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            if (onAudioTracks != null)
              Material(
                color: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: Icon(AppIcons.fileAudio, color: colors.textPrimary, size: 20),
                  onPressed: onAudioTracks,
                  tooltip: 'Audio Tracks',
                ),
              ),
            if (onSubtitles != null)
              Material(
                color: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: Icon(AppIcons.subtitles, color: colors.textPrimary, size: 20),
                  onPressed: onSubtitles,
                  tooltip: 'Subtitles',
                ),
              ),
            if (onRotate != null)
              Material(
                color: Colors.transparent,
                clipBehavior: Clip.antiAlias,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: Icon(AppIcons.rotate, color: colors.textPrimary, size: 20),
                  onPressed: onRotate,
                  tooltip: 'Rotate orientation',
                ),
              ),
            Material(
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              shape: const CircleBorder(),
              child: IconButton(
                icon: Icon(AppIcons.share, color: colors.textPrimary, size: 20),
                onPressed: onShare,
                tooltip: 'Share video',
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
            Material(
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              shape: const CircleBorder(),
              child: IconButton(
                icon: Icon(AppIcons.moreVert, color: colors.textPrimary, size: 20),
                onPressed: onMore,
                tooltip: 'More options',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
