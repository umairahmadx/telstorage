/*
 * File: video_progress_bar.dart
 * Description: Interactive scrubbing progress bar for video playback displaying timestamps and buffered ranges.
 */

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Progress bar widget managing video position seeking and duration formatting.
class VideoProgressBar extends StatelessWidget {
  /// Current playback position.
  final Duration position;

  /// Total video duration.
  final Duration duration;

  /// List of loaded buffered ranges.
  final List<DurationRange> buffered;

  /// Callback when user seeks to a new timestamp.
  final ValueChanged<Duration> onSeek;

  /// Constructs VideoProgressBar.
  const VideoProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
  });

  /// Formats duration into "mm:ss" or "hh:mm:ss".
  static String formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    final maxMs = duration.inMilliseconds.toDouble();
    final currentMs = position.inMilliseconds.toDouble().clamp(0.0, maxMs > 0 ? maxMs : 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            formatDuration(position),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: colors.accentPrimary,
                inactiveTrackColor: colors.borderSubtle.withValues(alpha: 0.35),
                thumbColor: colors.accentPrimary,
                overlayColor: colors.accentPrimary.withValues(alpha: 0.2),
              ),
              child: Slider(
                min: 0.0,
                max: maxMs > 0 ? maxMs : 1.0,
                value: currentMs,
                onChanged: maxMs > 0
                    ? (val) {
                        onSeek(Duration(milliseconds: val.round()));
                      }
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatDuration(duration),
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
