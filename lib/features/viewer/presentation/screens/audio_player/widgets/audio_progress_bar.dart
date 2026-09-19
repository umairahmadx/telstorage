/*
 * File: audio_progress_bar.dart
 * Description: Interactive audio progress bar rendering elapsed time, remaining time, chunk buffer indicators, and smooth touch-scrubbing.
 */

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Interactive scrubber bar for audio playback displaying buffered chunk segments and elapsed/remaining timestamps.
class AudioProgressBar extends StatefulWidget {
  /// Current playback position.
  final Duration position;

  /// Total duration of the track.
  final Duration duration;

  /// Cached and buffered duration segments.
  final List<DurationRange> mergedBuffered;

  /// Callback when user scrubs to a new duration.
  final ValueChanged<Duration> onSeek;

  /// Constructs AudioProgressBar.
  const AudioProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.mergedBuffered,
    required this.onSeek,
  });

  @override
  State<AudioProgressBar> createState() => _AudioProgressBarState();
}

class _AudioProgressBarState extends State<AudioProgressBar> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

  String _formatDuration(Duration d) {
    if (d < Duration.zero) d = Duration.zero;
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void _handleSeek(double fraction) {
    final totalMs = widget.duration.inMilliseconds;
    if (totalMs <= 0) return;
    final targetMs = (fraction.clamp(0.0, 1.0) * totalMs).round();
    widget.onSeek(Duration(milliseconds: targetMs));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final totalMs = widget.duration.inMilliseconds;
    final currentMs = widget.position.inMilliseconds;
    final progress = totalMs > 0
        ? (_isDragging ? _dragProgress : (currentMs / totalMs).clamp(0.0, 1.0))
        : 0.0;

    final elapsedStr = _formatDuration(
      _isDragging
          ? Duration(milliseconds: (totalMs * _dragProgress).round())
          : widget.position,
    );
    final remainingMs = totalMs - (_isDragging ? (totalMs * _dragProgress).round() : currentMs);
    final remainingStr = '-${_formatDuration(Duration(milliseconds: remainingMs.clamp(0, totalMs)))}';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null && box.hasSize && box.size.width > 0) {
              final frac = (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
              setState(() {
                _isDragging = true;
                _dragProgress = frac;
              });
            }
          },
          onHorizontalDragUpdate: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null && box.hasSize && box.size.width > 0) {
              final frac = (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
              setState(() {
                _dragProgress = frac;
              });
            }
          },
          onHorizontalDragEnd: (_) {
            if (_isDragging) {
              _handleSeek(_dragProgress);
              setState(() {
                _isDragging = false;
              });
            }
          },
          onTapDown: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box != null && box.hasSize && box.size.width > 0) {
              final frac = (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
              _handleSeek(frac);
            }
          },
          child: SizedBox(
            height: 28,
            child: Center(
              child: CustomPaint(
                size: const Size(double.infinity, 28),
                painter: _ProgressBarPainter(
                  progress: progress,
                  totalDuration: widget.duration,
                  mergedBuffered: widget.mergedBuffered,
                  trackColor: colors.bgSurfaceInset,
                  bufferColor: colors.accentPrimary.withValues(alpha: 0.28),
                  progressColor: colors.accentPrimary,
                  thumbColor: colors.textPrimary,
                  isDragging: _isDragging,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                elapsedStr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                totalMs > 0 ? remainingStr : '--:--',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double progress;
  final Duration totalDuration;
  final List<DurationRange> mergedBuffered;
  final Color trackColor;
  final Color bufferColor;
  final Color progressColor;
  final Color thumbColor;
  final bool isDragging;

  _ProgressBarPainter({
    required this.progress,
    required this.totalDuration,
    required this.mergedBuffered,
    required this.trackColor,
    required this.bufferColor,
    required this.progressColor,
    required this.thumbColor,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const barHeight = 4.0;
    const r = barHeight / 2;
    final y = size.height / 2;
    final totalMs = totalDuration.inMilliseconds;

    // 1. Background inactive track
    final trackPaint = Paint()..color = trackColor;
    final trackRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - r, size.width, barHeight),
      const Radius.circular(r),
    );
    canvas.drawRRect(trackRRect, trackPaint);

    // 2. Buffered chunk segments
    if (totalMs > 0 && mergedBuffered.isNotEmpty) {
      final bufferPaint = Paint()..color = bufferColor;
      for (final range in mergedBuffered) {
        final startFrac = (range.start.inMilliseconds / totalMs).clamp(0.0, 1.0);
        final endFrac = (range.end.inMilliseconds / totalMs).clamp(0.0, 1.0);
        final left = startFrac * size.width;
        final width = (endFrac - startFrac) * size.width;
        if (width > 0) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(left, y - r, width, barHeight),
              const Radius.circular(r),
            ),
            bufferPaint,
          );
        }
      }
    }

    // 3. Active progress bar
    final activeWidth = (progress * size.width).clamp(0.0, size.width);
    if (activeWidth > 0) {
      final progressPaint = Paint()..color = progressColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - r, activeWidth, barHeight),
          const Radius.circular(r),
        ),
        progressPaint,
      );
    }

    // 4. Scrubber Thumb
    final thumbX = activeWidth;
    final thumbRadius = isDragging ? 7.0 : 5.0;
    final thumbPaint = Paint()..color = thumbColor;
    canvas.drawCircle(Offset(thumbX, y), thumbRadius, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter old) {
    return old.progress != progress ||
        old.totalDuration != totalDuration ||
        old.mergedBuffered != mergedBuffered ||
        old.isDragging != isDragging ||
        old.progressColor != progressColor ||
        old.trackColor != trackColor;
  }
}
