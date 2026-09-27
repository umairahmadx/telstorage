/*
 * File: video_subtitle_sheet.dart
 * Description: Bottom sheet for subtitles: track selection, online search, local file picking, URL input, and sync delay adjustments.
 */

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../../../../../core/services/subtitle_service.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';
import 'video_online_subtitle_dialog.dart';

/// Modal bottom sheet allowing users to manage subtitles and fine-tune synchronization.
class VideoSubtitleSheet extends StatelessWidget {
  final String videoTitle;
  final List<SubtitleTrack> tracks;
  final SubtitleTrack? selectedTrack;
  final Duration subtitleDelay;
  final ValueChanged<SubtitleTrack> onTrackSelected;
  final ValueChanged<String> onExternalSubtitleLoaded;
  final ValueChanged<Duration> onDelayAdjusted;

  const VideoSubtitleSheet({
    super.key,
    required this.videoTitle,
    required this.tracks,
    required this.selectedTrack,
    required this.subtitleDelay,
    required this.onTrackSelected,
    required this.onExternalSubtitleLoaded,
    required this.onDelayAdjusted,
  });

  static void show(
    BuildContext context, {
    required String videoTitle,
    required List<SubtitleTrack> tracks,
    required SubtitleTrack? selectedTrack,
    required Duration subtitleDelay,
    required ValueChanged<SubtitleTrack> onTrackSelected,
    required ValueChanged<String> onExternalSubtitleLoaded,
    required ValueChanged<Duration> onDelayAdjusted,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VideoSubtitleSheet(
        videoTitle: videoTitle,
        tracks: tracks,
        selectedTrack: selectedTrack,
        subtitleDelay: subtitleDelay,
        onTrackSelected: onTrackSelected,
        onExternalSubtitleLoaded: onExternalSubtitleLoaded,
        onDelayAdjusted: onDelayAdjusted,
      ),
    );
  }

  String _formatTrackName(SubtitleTrack track) {
    if (track.id == 'no' || track.id == 'auto') return 'Subtitles Off';
    final title = track.title?.trim();
    final lang = track.language?.trim();
    if (title != null && title.isNotEmpty) {
      if (lang != null && lang.isNotEmpty) return '$title ($lang)';
      return title;
    }
    if (lang != null && lang.isNotEmpty) return 'Subtitles ($lang)';
    return 'Track ${track.id}';
  }

  void _promptUrlInput(BuildContext context, AppColorsExtension colors) {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSurface,
        title: Text('Enter Subtitle URL', style: TextStyle(color: colors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: textController,
          style: TextStyle(color: colors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'https://example.com/subs.srt',
            hintStyle: TextStyle(color: colors.textTertiary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.accentPrimary),
            onPressed: () async {
              final url = textController.text.trim();
              if (url.isNotEmpty) {
                Navigator.of(ctx).pop();
                try {
                  final path = await SubtitleService.instance.fetchSubtitleFromUrl(url);
                  onExternalSubtitleLoaded(path);
                } catch (_) {}
              }
            },
            child: const Text('Load'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(AppIcons.subtitles, color: colors.accentPrimary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Subtitles & Captions',
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

              // Subtitle Delay / Sync Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text('Sync Delay:', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                    const Spacer(),
                    IconButton(
                      icon: Icon(AppIcons.skipPrevious, color: colors.textPrimary, size: 18),
                      tooltip: '-250 ms',
                      onPressed: () => onDelayAdjusted(const Duration(milliseconds: -250)),
                    ),
                    IconButton(
                      icon: Icon(AppIcons.replay10, color: colors.textPrimary, size: 18),
                      tooltip: '-50 ms',
                      onPressed: () => onDelayAdjusted(const Duration(milliseconds: -50)),
                    ),
                    Text(
                      SubtitleService.formatDelay(subtitleDelay),
                      style: TextStyle(
                        color: colors.accentPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    IconButton(
                      icon: Icon(AppIcons.forward10, color: colors.textPrimary, size: 18),
                      tooltip: '+50 ms',
                      onPressed: () => onDelayAdjusted(const Duration(milliseconds: 50)),
                    ),
                    IconButton(
                      icon: Icon(AppIcons.skipNext, color: colors.textPrimary, size: 18),
                      tooltip: '+250 ms',
                      onPressed: () => onDelayAdjusted(const Duration(milliseconds: 250)),
                    ),
                  ],
                ),
              ),
              Divider(color: colors.borderSubtle, height: 1),

              // External Subtitle Actions
              ListTile(
                leading: Icon(AppIcons.search, color: colors.accentPrimary, size: 20),
                title: Text('Search Online Subtitles', style: TextStyle(color: colors.textPrimary, fontSize: 14)),
                onTap: () {
                  Navigator.of(context).pop();
                  VideoOnlineSubtitleDialog.show(
                    context,
                    videoTitle: videoTitle,
                    onSubtitleDownloaded: onExternalSubtitleLoaded,
                  );
                },
              ),
              ListTile(
                leading: Icon(AppIcons.folderOpen, color: colors.accentPrimary, size: 20),
                title: Text('Pick Local Subtitle File', style: TextStyle(color: colors.textPrimary, fontSize: 14)),
                onTap: () async {
                  Navigator.of(context).pop();
                  final path = await SubtitleService.instance.pickLocalSubtitleFile();
                  if (path != null) {
                    onExternalSubtitleLoaded(path);
                  }
                },
              ),
              ListTile(
                leading: Icon(AppIcons.link, color: colors.accentPrimary, size: 20),
                title: Text('Enter Subtitle URL', style: TextStyle(color: colors.textPrimary, fontSize: 14)),
                onTap: () {
                  Navigator.of(context).pop();
                  _promptUrlInput(context, colors);
                },
              ),
              Divider(color: colors.borderSubtle, height: 1),

              // Off Option
              ListTile(
                title: Text('Off', style: TextStyle(color: colors.textPrimary, fontSize: 14)),
                trailing: (selectedTrack == null || selectedTrack == SubtitleTrack.no())
                    ? Icon(AppIcons.check, color: colors.accentPrimary, size: 20)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  onTrackSelected(SubtitleTrack.no());
                },
              ),

              // Tracks List
              ...tracks.where((t) => t.id != 'no' && t.id != 'auto').map((track) {
                final isSelected = selectedTrack?.id == track.id;
                return ListTile(
                  title: Text(
                    _formatTrackName(track),
                    style: TextStyle(
                      color: isSelected ? colors.accentPrimary : colors.textPrimary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(AppIcons.check, color: colors.accentPrimary, size: 20)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    onTrackSelected(track);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
