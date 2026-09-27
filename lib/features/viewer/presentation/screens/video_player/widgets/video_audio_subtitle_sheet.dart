/*
 * File: video_audio_subtitle_sheet.dart
 * Description: Unified bottom sheet for Audio and Subtitles supporting responsive portrait and 2-column landscape layouts.
 */

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../../../../../core/services/subtitle_service.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';
import 'video_online_subtitle_dialog.dart';

/// Modal bottom sheet unifying Audio Track selection and Subtitle configurations.
class VideoAudioSubtitleSheet extends StatelessWidget {
  final String videoTitle;
  final List<AudioTrack> audioTracks;
  final AudioTrack? selectedAudioTrack;
  final ValueChanged<AudioTrack> onAudioTrackSelected;

  final List<SubtitleTrack> subtitleTracks;
  final SubtitleTrack? selectedSubtitleTrack;
  final Duration subtitleDelay;
  final ValueChanged<SubtitleTrack> onSubtitleTrackSelected;
  final ValueChanged<String> onExternalSubtitleLoaded;
  final ValueChanged<Duration> onDelayAdjusted;

  const VideoAudioSubtitleSheet({
    super.key,
    required this.videoTitle,
    required this.audioTracks,
    required this.selectedAudioTrack,
    required this.onAudioTrackSelected,
    required this.subtitleTracks,
    required this.selectedSubtitleTrack,
    required this.subtitleDelay,
    required this.onSubtitleTrackSelected,
    required this.onExternalSubtitleLoaded,
    required this.onDelayAdjusted,
  });

  /// Displays the unified audio and subtitle sheet.
  static void show(
    BuildContext context, {
    required String videoTitle,
    required List<AudioTrack> audioTracks,
    required AudioTrack? selectedAudioTrack,
    required ValueChanged<AudioTrack> onAudioTrackSelected,
    required List<SubtitleTrack> subtitleTracks,
    required SubtitleTrack? selectedSubtitleTrack,
    required Duration subtitleDelay,
    required ValueChanged<SubtitleTrack> onSubtitleTrackSelected,
    required ValueChanged<String> onExternalSubtitleLoaded,
    required ValueChanged<Duration> onDelayAdjusted,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VideoAudioSubtitleSheet(
        videoTitle: videoTitle,
        audioTracks: audioTracks,
        selectedAudioTrack: selectedAudioTrack,
        onAudioTrackSelected: onAudioTrackSelected,
        subtitleTracks: subtitleTracks,
        selectedSubtitleTrack: selectedSubtitleTrack,
        subtitleDelay: subtitleDelay,
        onSubtitleTrackSelected: onSubtitleTrackSelected,
        onExternalSubtitleLoaded: onExternalSubtitleLoaded,
        onDelayAdjusted: onDelayAdjusted,
      ),
    );
  }

  String _formatAudioName(AudioTrack track) {
    if (track.id == 'no' || track.id == 'auto') return 'Disable track';
    final title = track.title?.trim();
    final lang = track.language?.trim();
    if (title != null && title.isNotEmpty) {
      if (lang != null && lang.isNotEmpty) return '$title ($lang)';
      return title;
    }
    if (lang != null && lang.isNotEmpty) return 'Audio ($lang)';
    return 'Audio Track ${track.id}';
  }

  String _formatSubtitleName(SubtitleTrack track) {
    if (track.id == 'no' || track.id == 'auto') return 'No track';
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
        title: Text(
          'Enter Subtitle URL',
          style: TextStyle(color: colors.textPrimary, fontSize: 16),
        ),
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

  Widget _buildAudioSection(BuildContext context, AppColorsExtension colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(AppIcons.fileAudio, color: colors.accentPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Audio',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Divider(color: colors.borderSubtle, height: 1),
        // Disable option
        ListTile(
          dense: true,
          title: Text(
            'Disable track',
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
          ),
          trailing: (selectedAudioTrack == null || selectedAudioTrack?.id == 'no')
              ? Icon(AppIcons.check, color: colors.accentPrimary, size: 18)
              : null,
          onTap: () {
            Navigator.of(context).pop();
            onAudioTrackSelected(AudioTrack.no());
          },
        ),
        // Active audio tracks
        ...audioTracks.where((t) => t.id != 'no').map((track) {
          final isSelected = selectedAudioTrack?.id == track.id;
          return ListTile(
            dense: true,
            title: Text(
              _formatAudioName(track),
              style: TextStyle(
                color: isSelected ? colors.accentPrimary : colors.textPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            trailing: isSelected
                ? Icon(AppIcons.check, color: colors.accentPrimary, size: 18)
                : null,
            onTap: () {
              Navigator.of(context).pop();
              onAudioTrackSelected(track);
            },
          );
        }),
      ],
    );
  }

  Widget _buildSubtitleSection(BuildContext context, AppColorsExtension colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(AppIcons.subtitles, color: colors.accentPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Subtitles',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Divider(color: colors.borderSubtle, height: 1),
        // No track option
        ListTile(
          dense: true,
          title: Text(
            'No track',
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
          ),
          trailing: (selectedSubtitleTrack == null || selectedSubtitleTrack?.id == 'no')
              ? Icon(AppIcons.check, color: colors.accentPrimary, size: 18)
              : null,
          onTap: () {
            Navigator.of(context).pop();
            onSubtitleTrackSelected(SubtitleTrack.no());
          },
        ),
        // Subtitle tracks
        ...subtitleTracks.where((t) => t.id != 'no' && t.id != 'auto').map((track) {
          final isSelected = selectedSubtitleTrack?.id == track.id;
          return ListTile(
            dense: true,
            title: Text(
              _formatSubtitleName(track),
              style: TextStyle(
                color: isSelected ? colors.accentPrimary : colors.textPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            trailing: isSelected
                ? Icon(AppIcons.check, color: colors.accentPrimary, size: 18)
                : null,
            onTap: () {
              Navigator.of(context).pop();
              onSubtitleTrackSelected(track);
            },
          );
        }),
        Divider(color: colors.borderSubtle, height: 1),
        // Delay controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Text(
                'Sync:',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(AppIcons.skipPrevious, color: colors.textPrimary, size: 16),
                tooltip: '-250 ms',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () => onDelayAdjusted(const Duration(milliseconds: -250)),
              ),
              const SizedBox(width: 8),
              Text(
                SubtitleService.formatDelay(subtitleDelay),
                style: TextStyle(
                  color: colors.accentPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(AppIcons.skipNext, color: colors.textPrimary, size: 16),
                tooltip: '+250 ms',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: () => onDelayAdjusted(const Duration(milliseconds: 250)),
              ),
            ],
          ),
        ),
        Divider(color: colors.borderSubtle, height: 1),
        // External Subtitle Actions
        ListTile(
          dense: true,
          leading: Icon(AppIcons.search, color: colors.accentPrimary, size: 18),
          title: Text(
            'Search subtitles online',
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
          ),
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
          dense: true,
          leading: Icon(AppIcons.folderOpen, color: colors.accentPrimary, size: 18),
          title: Text(
            'Load from storage',
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
          ),
          onTap: () async {
            Navigator.of(context).pop();
            final path = await SubtitleService.instance.pickLocalSubtitleFile();
            if (path != null) {
              onExternalSubtitleLoaded(path);
            }
          },
        ),
        ListTile(
          dense: true,
          leading: Icon(AppIcons.link, color: colors.accentPrimary, size: 18),
          title: Text(
            'Enter subtitle URL',
            style: TextStyle(color: colors.textPrimary, fontSize: 13),
          ),
          onTap: () {
            Navigator.of(context).pop();
            _promptUrlInput(context, colors);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxHeight: size.height * 0.85),
        child: Material(
          color: colors.bgSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: isLandscape
              // Landscape: 2-column split
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 1,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: _buildAudioSection(context, colors),
                        ),
                      ),
                      VerticalDivider(color: colors.borderSubtle, width: 1),
                      Expanded(
                        flex: 1,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: _buildSubtitleSection(context, colors),
                        ),
                      ),
                    ],
                  ),
                )
              // Portrait: Stacked
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAudioSection(context, colors),
                      Divider(color: colors.borderSubtle, thickness: 2, height: 16),
                      _buildSubtitleSection(context, colors),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
