import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Animated gradient storage ring.
/// Shows "Unlimited Storage" when [limitMb] is very large (>= 1TB).
class StorageRing extends StatefulWidget {
  final double usedMb;
  final double limitMb;

  const StorageRing({super.key, required this.usedMb, required this.limitMb});

  @override
  State<StorageRing> createState() => _StorageRingState();
}

class _StorageRingState extends State<StorageRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  double get _percent =>
      widget.limitMb <
          1e6 // show real % only for non-unlimited
      ? (widget.usedMb / widget.limitMb).clamp(0.0, 1.0)
      : 0.0; // unlimited: ring is decorative only

  bool get _isUnlimited => widget.limitMb >= 1e6;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final usedLabel = _formatSize(widget.usedMb);

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(200, 200),
                painter: _RingPainter(
                  percent: _isUnlimited ? 0.72 : _percent * _anim.value,
                  isDark: isDark,
                  isUnlimited: _isUnlimited,
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isUnlimited
                        ? '∞'
                        : '${(_percent * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: _isUnlimited ? 44 : 36,
                      fontWeight: FontWeight.w800,
                      foreground: Paint()
                        ..shader = const LinearGradient(
                          colors: [AppTheme.primary, Color(0xFFA78BFA)],
                        ).createShader(const Rect.fromLTWH(0, 0, 80, 40)),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isUnlimited ? 'Unlimited' : usedLabel,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    _isUnlimited
                        ? 'Storage'
                        : 'of ${_formatSize(widget.limitMb)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatSize(double mb) {
    if (mb >= 1024 * 1024) return '${(mb / 1024 / 1024).toStringAsFixed(1)} TB';
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }
}

class _RingPainter extends CustomPainter {
  final double percent;
  final bool isDark;
  final bool isUnlimited;

  _RingPainter({
    required this.percent,
    required this.isDark,
    required this.isUnlimited,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;
    const sw = 18.0;

    // Track
    final trackPaint = Paint()
      ..color = isDark ? const Color(0xFF2A2A45) : const Color(0xFFE8E4FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    // Glow (soft shadow behind arc)
    final glowPaint = Paint()
      ..color = AppTheme.primary.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw + 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    // Gradient arc
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * percent;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      glowPaint,
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradPaint = Paint()
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: 2 * math.pi,
        colors: [Color(0xFF6C63FF), Color(0xFFA78BFA), Color(0xFF6C63FF)],
        stops: [0.0, 0.6, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, gradPaint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.percent != percent || old.isDark != isDark;
}
