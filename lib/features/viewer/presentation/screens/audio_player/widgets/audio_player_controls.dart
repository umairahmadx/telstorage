/*
 * File: audio_player_controls.dart
 * Description: Main transport control buttons for AudioPlayerScreen including previous/next, +/-10s seek, and play/pause button with ripple feedback.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Main media playback controls bar for audio player.
class AudioPlayerControls extends StatelessWidget {
  /// Whether audio is currently playing.
  final bool isPlaying;

  /// Whether audio is buffering.
  final bool isBuffering;

  /// Callback when play/pause is toggled.
  final VoidCallback onTogglePlay;

  /// Callback to skip to previous track.
  final VoidCallback onPrevious;

  /// Callback to skip to next track.
  final VoidCallback onNext;

  /// Callback to seek backward 10s.
  final VoidCallback onSkipBackward;

  /// Callback to seek forward 10s.
  final VoidCallback onSkipForward;

  /// Whether previous track action is enabled.
  final bool canPrevious;

  /// Whether next track action is enabled.
  final bool canNext;

  /// Constructs AudioPlayerControls.
  const AudioPlayerControls({
    super.key,
    required this.isPlaying,
    required this.isBuffering,
    required this.onTogglePlay,
    required this.onPrevious,
    required this.onNext,
    required this.onSkipBackward,
    required this.onSkipForward,
    this.canPrevious = true,
    this.canNext = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Previous track
        IconButton(
          onPressed: canPrevious ? onPrevious : null,
          iconSize: 28,
          icon: Icon(
            AppIcons.skipPrevious,
            color: canPrevious ? colors.textPrimary : colors.textTertiary,
          ),
          splashRadius: 24,
        ),

        // Skip backward 10s
        IconButton(
          onPressed: onSkipBackward,
          iconSize: 28,
          icon: Icon(
            AppIcons.replay10,
            color: colors.textPrimary,
          ),
          splashRadius: 24,
        ),

        // Play / Pause prominent button
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accentPrimary,
              boxShadow: [
                BoxShadow(
                  color: colors.accentPrimary.withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTogglePlay,
              child: Center(
                child: isBuffering
                    ? SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          valueColor: AlwaysStoppedAnimation<Color>(colors.bgPrimary),
                        ),
                      )
                    : Icon(
                        isPlaying ? AppIcons.pause : AppIcons.play,
                        size: 36,
                        color: colors.bgPrimary,
                      ),
              ),
            ),
          ),
        ),

        // Skip forward 10s
        IconButton(
          onPressed: onSkipForward,
          iconSize: 28,
          icon: Icon(
            AppIcons.forward10,
            color: colors.textPrimary,
          ),
          splashRadius: 24,
        ),

        // Next track
        IconButton(
          onPressed: canNext ? onNext : null,
          iconSize: 28,
          icon: Icon(
            AppIcons.skipNext,
            color: canNext ? colors.textPrimary : colors.textTertiary,
          ),
          splashRadius: 24,
        ),
      ],
    );
  }
}
