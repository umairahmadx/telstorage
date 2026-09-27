/*
 * File: video_progress_bar.dart
 * Description: Interactive scrubbing progress bar for video playback displaying timestamps and buffered ranges.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/models/video_stream_models.dart';
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

  /// Whether the video is currently in landscape orientation.
  final bool isLandscape;

  /// Optional callback to toggle orientation (YouTube style).
  final VoidCallback? onRotate;

  /// Constructs VideoProgressBar.
  const VideoProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
    this.isLandscape = false,
    this.onRotate,
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
                trackShape: YouTubeSliderTrackShape(
                  buffered: buffered,
                  duration: duration,
                  bufferedColor: colors.textSecondary.withValues(alpha: 0.45),
                ),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: colors.accentPrimary,
                inactiveTrackColor: colors.borderSubtle.withValues(alpha: 0.30),
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
          if (onRotate != null) ...[
            const SizedBox(width: 6),
            Material(
              color: Colors.transparent,
              clipBehavior: Clip.antiAlias,
              shape: const CircleBorder(),
              child: IconButton(
                icon: Icon(
                  isLandscape
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: colors.textPrimary,
                  size: 22,
                ),
                tooltip: 'Rotate orientation',
                onPressed: onRotate,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Custom slider track shape rendering YouTube-style multi-range buffer segments
/// alongside active playback and inactive background tracks.
class YouTubeSliderTrackShape extends RoundedRectSliderTrackShape {
  /// Loaded duration ranges to paint as translucent buffer segments.
  final List<DurationRange> buffered;

  /// Total duration of the video.
  final Duration duration;

  /// Color used to paint buffered segments.
  final Color bufferedColor;

  /// Constructs YouTubeSliderTrackShape.
  const YouTubeSliderTrackShape({
    required this.buffered,
    required this.duration,
    required this.bufferedColor,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final trackRadius = Radius.circular(trackRect.height / 2);

    // 1. Inactive background track (unbuffered)
    if (sliderTheme.inactiveTrackColor != null) {
      final inactivePaint = Paint()..color = sliderTheme.inactiveTrackColor!;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(trackRect, trackRadius),
        inactivePaint,
      );
    }

    // 2. Buffered ranges (downloaded chunks)
    final totalMs = duration.inMilliseconds;
    if (totalMs > 0 && buffered.isNotEmpty) {
      final bufferPaint = Paint()..color = bufferedColor;
      for (final range in buffered) {
        final startFrac =
            (range.start.inMilliseconds / totalMs).clamp(0.0, 1.0);
        final endFrac = (range.end.inMilliseconds / totalMs).clamp(0.0, 1.0);
        if (endFrac > startFrac) {
          final left = trackRect.left + trackRect.width * startFrac;
          final right = trackRect.left + trackRect.width * endFrac;
          final bufferRect =
              Rect.fromLTRB(left, trackRect.top, right, trackRect.bottom);
          context.canvas.drawRRect(
            RRect.fromRectAndRadius(bufferRect, trackRadius),
            bufferPaint,
          );
        }
      }
    }

    // 3. Active played track (up to thumb center)
    if (sliderTheme.activeTrackColor != null) {
      final activeRect = Rect.fromLTRB(
        trackRect.left,
        trackRect.top - (additionalActiveTrackHeight / 2),
        thumbCenter.dx.clamp(trackRect.left, trackRect.right),
        trackRect.bottom + (additionalActiveTrackHeight / 2),
      );
      final activePaint = Paint()..color = sliderTheme.activeTrackColor!;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, trackRadius),
        activePaint,
      );
    }
  }
}
