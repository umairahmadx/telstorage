/*
 * File: video_player_controls_overlay.dart
 * Description: Centered video playback controls featuring play, pause, 10-second skip actions, and live buffering spinner.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Centered playback overlay with glassmorphic buttons and ripple feedback.
class VideoPlayerControlsOverlay extends StatelessWidget {
  /// Whether video is currently playing.
  final bool isPlaying;

  /// Whether video is waiting on buffer.
  final bool isBuffering;

  /// Whether controls are visible.
  final bool isVisible;

  /// Callback to toggle play/pause.
  final VoidCallback onPlayPause;

  /// Callback to jump forward 10 seconds.
  final VoidCallback onSkipForward;

  /// Callback to jump backward 10 seconds.
  final VoidCallback onSkipBackward;

  /// Constructs VideoPlayerControlsOverlay.
  const VideoPlayerControlsOverlay({
    super.key,
    required this.isPlaying,
    required this.isBuffering,
    required this.isVisible,
    required this.onPlayPause,
    required this.onSkipForward,
    required this.onSkipBackward,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Center(
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !isVisible,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rewind 10s
              _buildControlButton(
                context: context,
                icon: Icons.replay_10_rounded,
                tooltip: 'Rewind 10s',
                onTap: onSkipBackward,
                size: 48,
                iconSize: 26,
              ),
              const SizedBox(width: 24),
              // Play / Pause / Buffering
              _buildMainPlayButton(context, colors),
              const SizedBox(width: 24),
              // Fast forward 10s
              _buildControlButton(
                context: context,
                icon: Icons.forward_10_rounded,
                tooltip: 'Forward 10s',
                onTap: onSkipForward,
                size: 48,
                iconSize: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainPlayButton(BuildContext context, AppColorsExtension colors) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: colors.bgPrimary.withValues(alpha: 0.65),
        shape: BoxShape.circle,
        border: Border.all(
          color: colors.borderSubtle.withValues(alpha: 0.25),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPlayPause,
          child: Center(
            child: isBuffering
                ? SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: colors.textPrimary,
                    size: 40,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required double size,
    required double iconSize,
  }) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.bgPrimary.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Center(
            child: Icon(
              icon,
              color: colors.textPrimary,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}
