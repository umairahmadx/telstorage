/*
 * File: video_audio_track_sheet.dart
 * Description: Modal bottom sheet for switching active audio tracks in multi-language videos.
 */

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Modal bottom sheet allowing users to switch between multi-audio tracks.
class VideoAudioTrackSheet extends StatelessWidget {
  final List<AudioTrack> tracks;
  final AudioTrack? selectedTrack;
  final ValueChanged<AudioTrack> onTrackSelected;

  const VideoAudioTrackSheet({
    super.key,
    required this.tracks,
    required this.selectedTrack,
    required this.onTrackSelected,
  });

  static void show(
    BuildContext context, {
    required List<AudioTrack> tracks,
    required AudioTrack? selectedTrack,
    required ValueChanged<AudioTrack> onTrackSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VideoAudioTrackSheet(
        tracks: tracks,
        selectedTrack: selectedTrack,
        onTrackSelected: onTrackSelected,
      ),
    );
  }

  String _formatTrackName(AudioTrack track) {
    final title = track.title?.trim();
    final lang = track.language?.trim();
    if (title != null && title.isNotEmpty) {
      if (lang != null && lang.isNotEmpty) return '$title ($lang)';
      return title;
    }
    if (lang != null && lang.isNotEmpty) return 'Audio ($lang)';
    return 'Audio Track ${track.id}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(AppIcons.fileAudio, color: colors.accentPrimary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Audio Tracks',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: colors.borderSubtle, height: 1),
            if (tracks.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No alternate audio tracks available',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: tracks.map((track) {
                    final isSelected = selectedTrack?.id == track.id;
                    return Material(
                      color: Colors.transparent,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        title: Text(
                          _formatTrackName(track),
                          style: TextStyle(
                            color: isSelected ? colors.accentPrimary : colors.textPrimary,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(AppIcons.check, color: colors.accentPrimary, size: 20)
                            : null,
                        onTap: () {
                          Navigator.of(context).pop();
                          onTrackSelected(track);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
