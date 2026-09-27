/*
 * File: video_speed_dialog.dart
 * Description: Interactive dialog for fine-grained playback speed adjustment with steppers, continuous slider, and presets.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Modal dialog allowing users to adjust video playback speed from 0.25x to 8.00x.
class VideoSpeedDialog extends StatefulWidget {
  final double currentSpeed;
  final ValueChanged<double> onSpeedSelected;

  const VideoSpeedDialog({
    super.key,
    required this.currentSpeed,
    required this.onSpeedSelected,
  });

  /// Displays the speed dialog modally.
  static Future<void> show(
    BuildContext context, {
    required double currentSpeed,
    required ValueChanged<double> onSpeedSelected,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.70),
      builder: (ctx) => VideoSpeedDialog(
        currentSpeed: currentSpeed,
        onSpeedSelected: onSpeedSelected,
      ),
    );
  }

  @override
  State<VideoSpeedDialog> createState() => _VideoSpeedDialogState();
}

class _VideoSpeedDialogState extends State<VideoSpeedDialog> {
  late double _speed;
  static const double _minSpeed = 0.25;
  static const double _maxSpeed = 8.00;
  static const List<double> _presets = [0.8, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _speed = widget.currentSpeed.clamp(_minSpeed, _maxSpeed);
  }

  void _updateSpeed(double newSpeed) {
    final clamped = double.parse(newSpeed.clamp(_minSpeed, _maxSpeed).toStringAsFixed(2));
    setState(() => _speed = clamped);
    widget.onSpeedSelected(clamped);
  }

  void _stepSpeed(double delta) {
    _updateSpeed(_speed + delta);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final formattedSpeed = _speed.toStringAsFixed(2);

    return Dialog(
      backgroundColor: colors.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.borderSubtle.withValues(alpha: 0.60)),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Playback speed',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.textSecondary, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Center Readout with Steppers
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Material(
                    color: colors.bgPrimary.withValues(alpha: 0.50),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      icon: Icon(Icons.chevron_left_rounded, color: colors.textPrimary, size: 26),
                      onPressed: _speed > _minSpeed ? () => _stepSpeed(-0.05) : null,
                      tooltip: 'Decrease speed',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          formattedSpeed,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          'x',
                          style: TextStyle(
                            color: colors.accentPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: colors.bgPrimary.withValues(alpha: 0.50),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      icon: Icon(Icons.chevron_right_rounded, color: colors.textPrimary, size: 26),
                      onPressed: _speed < _maxSpeed ? () => _stepSpeed(0.05) : null,
                      tooltip: 'Increase speed',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: colors.accentPrimary,
                  inactiveTrackColor: colors.borderSubtle.withValues(alpha: 0.50),
                  thumbColor: colors.accentPrimary,
                  overlayColor: colors.accentPrimary.withValues(alpha: 0.15),
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: _speed,
                  min: _minSpeed,
                  max: _maxSpeed,
                  onChanged: (val) => _updateSpeed(val),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_minSpeed.toStringAsFixed(2)}x',
                      style: TextStyle(color: colors.textTertiary, fontSize: 12),
                    ),
                    Text(
                      '${_maxSpeed.toStringAsFixed(2)}x',
                      style: TextStyle(color: colors.textTertiary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Preset Pills
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _presets.map((preset) {
                    final isSelected = (_speed - preset).abs() < 0.04;
                    final borderRadius = BorderRadius.circular(16);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Material(
                        color: isSelected
                            ? colors.accentPrimary
                            : colors.bgPrimary.withValues(alpha: 0.60),
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: borderRadius,
                          side: BorderSide(
                            color: isSelected
                                ? colors.accentPrimary
                                : colors.borderSubtle.withValues(alpha: 0.60),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: borderRadius,
                          onTap: () => _updateSpeed(preset),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            child: Text(
                              '${preset}x',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.white
                                    : colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
