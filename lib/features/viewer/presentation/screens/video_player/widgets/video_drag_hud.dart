/*
 * File: video_drag_hud.dart
 * Description: On-screen HUD displaying scrub delta and target duration during viewport drag gestures.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Heads-Up Display overlay rendered when scrubbing forward or backward across the video viewport.
class VideoDragHud extends StatelessWidget {
  /// Whether the drag gesture is active.
  final bool isVisible;

  /// Time offset difference from drag origin (positive or negative).
  final Duration dragDelta;

  /// Target playback timestamp resulting from drag.
  final Duration targetPosition;

  /// Total video duration.
  final Duration totalDuration;

  const VideoDragHud({
    super.key,
    required this.isVisible,
    required this.dragDelta,
    required this.targetPosition,
    required this.totalDuration,
  });

  String _formatDuration(Duration d) {
    final negative = d.isNegative;
    final abs = d.abs();
    final m = abs.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = abs.inSeconds.remainder(60).toString().padLeft(2, '0');
    final prefix = negative ? '-' : '+';
    if (abs.inHours > 0) {
      final h = abs.inHours.toString().padLeft(2, '0');
      return '$prefix$h:$m:$s';
    }
    return '$prefix$m:$s';
  }

  String _formatTimestamp(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final h = d.inHours.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isForward = !dragDelta.isNegative;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: colors.bgPrimary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: colors.bgPrimary.withValues(alpha: 0.6),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isForward ? AppIcons.forward10 : AppIcons.replay10,
              color: colors.accentPrimary,
              size: 36,
            ),
            const SizedBox(height: 8),
            Text(
              _formatDuration(dragDelta),
              style: TextStyle(
                color: colors.accentPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_formatTimestamp(targetPosition)} / ${_formatTimestamp(totalDuration)}',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
