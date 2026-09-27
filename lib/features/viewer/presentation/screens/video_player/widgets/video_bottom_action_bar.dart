/*
 * File: video_bottom_action_bar.dart
 * Description: Clean, borderless bottom action row for VideoPlayer with evenly spaced, enlarged icons for Audio/Subs, Speed, Aspect Ratio, and streaming status.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../models/video_aspect_ratio_mode.dart';

/// Clean bottom action bar distributing large borderless controls evenly across the entire row.
class VideoBottomActionBar extends StatelessWidget {
  /// Current playback speed rate.
  final double playbackSpeed;

  /// Current aspect ratio scaling mode.
  final VideoAspectRatioMode aspectRatioMode;

  /// Callback to change playback speed (opens speed dialog).
  final VoidCallback onSpeed;

  /// Callback to directly cycle aspect ratio.
  final VoidCallback onAspectRatioToggle;

  /// Callback to open unified audio & subtitle sheet.
  final VoidCallback? onAudioSubtitles;

  /// Number of chunks currently cached in local storage.
  final int cachedChunks;

  /// Total number of chunks for the video.
  final int totalChunks;

  /// Cached MBs downloaded so far.
  final double cachedMb;

  /// Total file size in MBs.
  final double totalMb;

  /// Callback to open chunk cache inspector.
  final VoidCallback? onCacheInspector;

  /// Constructs VideoBottomActionBar.
  const VideoBottomActionBar({
    super.key,
    required this.playbackSpeed,
    required this.aspectRatioMode,
    required this.onSpeed,
    required this.onAspectRatioToggle,
    this.onAudioSubtitles,
    required this.cachedChunks,
    required this.totalChunks,
    required this.cachedMb,
    required this.totalMb,
    this.onCacheInspector,
  });

  Widget _buildIconButton({
    required BuildContext context,
    required AppColorsExtension colors,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    double size = 26,
  }) {
    final borderRadius = BorderRadius.circular(24);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Icon(
              icon,
              size: size,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedButton({
    required BuildContext context,
    required AppColorsExtension colors,
  }) {
    final borderRadius = BorderRadius.circular(20);
    final speedStr = '${playbackSpeed == 1.0 ? '1.0' : playbackSpeed.toString()}x';

    return Tooltip(
      message: 'Speed ($speedStr)',
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onSpeed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  AppIcons.speed,
                  size: 24,
                  color: colors.textPrimary,
                ),
                const SizedBox(width: 4),
                Text(
                  speedStr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreamingBadge(BuildContext context, AppColorsExtension colors) {
    final borderRadius = BorderRadius.circular(20);
    final isComplete = cachedChunks >= totalChunks && totalChunks > 0;
    final mbDisplay = isComplete
        ? '${totalMb.toStringAsFixed(0)} MB'
        : '${cachedMb.toStringAsFixed(0)}/${totalMb.toStringAsFixed(0)} MB';

    return Tooltip(
      message: 'Chunk Cache Inspector ($cachedChunks/$totalChunks Chunks)',
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onCacheInspector,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isComplete ? Icons.check_circle_outline_rounded : Icons.cloud_sync_outlined,
                  size: 18,
                  color: isComplete ? colors.accentPrimary : colors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  '$cachedChunks/$totalChunks ($mbDisplay)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isComplete ? colors.accentPrimary : colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Button 1: Audio & Subtitles
          if (onAudioSubtitles != null)
            _buildIconButton(
              context: context,
              colors: colors,
              icon: AppIcons.subtitles,
              tooltip: 'Audio & Subtitles',
              onTap: onAudioSubtitles,
              size: 26,
            ),

          // Button 2: Speed
          _buildSpeedButton(
            context: context,
            colors: colors,
          ),

          // Button 3: Aspect Ratio (direct toggle, plain clickable button)
          _buildIconButton(
            context: context,
            colors: colors,
            icon: Icons.aspect_ratio_rounded,
            tooltip: 'Aspect: ${aspectRatioMode.label}',
            onTap: onAspectRatioToggle,
            size: 26,
          ),

          // Button 4: Cache Badge
          _buildStreamingBadge(context, colors),
        ],
      ),
    );
  }
}
