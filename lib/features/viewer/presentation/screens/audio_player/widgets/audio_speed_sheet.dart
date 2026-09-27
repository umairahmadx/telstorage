/*
 * File: audio_speed_sheet.dart
 * Description: Modal bottom sheet for adjusting audio playback speeds.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../viewmodel/audio_player_view_model.dart';

/// Modal bottom sheet for selecting playback speed.
class AudioSpeedSheet extends StatelessWidget {
  final AudioPlayerViewModel viewModel;

  const AudioSpeedSheet({super.key, required this.viewModel});

  static const List<double> speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  static void show(BuildContext context, AudioPlayerViewModel viewModel) {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AudioSpeedSheet(viewModel: viewModel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Playback Speed',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          ...speeds.map(
            (spd) => ListTile(
              title: Text(
                '${spd}x',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: viewModel.playbackSpeed == spd
                      ? FontWeight.w700
                      : FontWeight.normal,
                  color: viewModel.playbackSpeed == spd
                      ? colors.accentPrimary
                      : colors.textPrimary,
                ),
              ),
              onTap: () {
                viewModel.setSpeed(spd);
                Navigator.of(context).pop();
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
