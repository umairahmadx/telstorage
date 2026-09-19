/*
 * File: audio_player_screen.dart
 * Description: Fullscreen translucent in-app audio player featuring chunk streaming, interactive scrubber, vinyl visualizer, and playlist controls.
 */

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/services/service_locator.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/thumbnail_widget.dart';
import 'viewmodel/audio_player_view_model.dart';
import 'widgets/audio_player_controls.dart';
import 'widgets/audio_progress_bar.dart';

/// Fullscreen audio player screen providing chunk-level streaming and playlist management.
class AudioPlayerScreen extends StatefulWidget {
  /// List of audio tracks in current directory.
  final List<FileRecord> tracks;

  /// Index of initially selected audio track.
  final int initialIndex;

  /// Optional prefix to namespace Hero transition tag.
  final String? heroPrefix;

  /// Optional injected ViewModel for testing.
  final AudioPlayerViewModel? viewModel;

  /// Constructs AudioPlayerScreen.
  const AudioPlayerScreen({
    super.key,
    required this.tracks,
    required this.initialIndex,
    this.heroPrefix,
    this.viewModel,
  });

  /// Opens AudioPlayerScreen with a smooth translucent route transition.
  static void open(
    BuildContext context, {
    required List<FileRecord> tracks,
    required int initialIndex,
    String? heroPrefix,
  }) {
    if (tracks.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (ctx, anim1, anim2) => FadeTransition(
          opacity: anim1,
          child: AudioPlayerScreen(
            tracks: tracks,
            initialIndex: initialIndex.clamp(0, tracks.length - 1),
            heroPrefix: heroPrefix,
          ),
        ),
      ),
    );
  }

  /// Checks if a given FileRecord represents a playable audio file.
  static bool isAudioRecord(FileRecord file) {
    if (file.isAudio) return true;
    final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
    return const {'mp3', 'm4a', 'aac', 'flac', 'ogg', 'oga', 'opus', 'wav'}.contains(ext);
  }

  @override
  State<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends State<AudioPlayerScreen>
    with SingleTickerProviderStateMixin {
  late final AudioPlayerViewModel _viewModel;
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );

    if (ServiceLocator.instance.isInitialized) {
      ServiceLocator.instance.thumbnailRepository.pauseDownloads();
    }

    _viewModel = widget.viewModel ?? AudioPlayerViewModel();
    _viewModel.addListener(_onViewModelChanged);

    if (widget.viewModel == null) {
      _viewModel.initialize(widget.tracks, widget.initialIndex);
    }
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    if (_viewModel.isPlaying) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat();
      }
    } else {
      if (_rotationController.isAnimating) {
        _rotationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _viewModel.removeListener(_onViewModelChanged);
    if (widget.viewModel == null) {
      _viewModel.dispose();
    }
    if (ServiceLocator.instance.isInitialized) {
      ServiceLocator.instance.thumbnailRepository.resumeDownloads();
    }
    super.dispose();
  }

  void _showPlaylistSheet() {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Playlist (${_viewModel.playlist.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: Icon(AppIcons.close, color: colors.textSecondary),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _viewModel.playlist.length,
                  itemBuilder: (context, idx) {
                    final item = _viewModel.playlist[idx];
                    final isCurrent = idx == _viewModel.currentIndex;
                    return ListTile(
                      leading: Icon(
                        isCurrent ? AppIcons.play : AppIcons.fileAudio,
                        color: isCurrent ? colors.accentPrimary : colors.textSecondary,
                      ),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                          color: isCurrent ? colors.accentPrimary : colors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        item.formattedSize,
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _viewModel.selectTrack(idx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSpeedSheet() {
    final colors = context.colors;
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
                    fontWeight: _viewModel.playbackSpeed == spd
                        ? FontWeight.w700
                        : FontWeight.normal,
                    color: _viewModel.playbackSpeed == spd
                        ? colors.accentPrimary
                        : colors.textPrimary,
                  ),
                ),
                onTap: () {
                  _viewModel.setSpeed(spd);
                  Navigator.of(ctx).pop();
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildArtwork(FileRecord track, AppColorsExtension colors) {
    final heroTag = widget.heroPrefix != null
        ? '${widget.heroPrefix}_audio_hero_${track.fileId}'
        : 'audio_hero_${track.fileId}';

    return Center(
      child: Hero(
        tag: heroTag,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.bgSurfaceInset,
              boxShadow: [
                BoxShadow(
                  color: colors.accentPrimary.withValues(alpha: 0.22),
                  blurRadius: 32,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: RotationTransition(
              turns: _rotationController,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.accentPrimary.withValues(alpha: 0.35),
                    width: 2.5,
                  ),
                ),
                child: track.thumbnailFileId != null
                    ? ClipOval(
                        child: ThumbnailWidget(
                          file: track,
                          width: 200,
                          height: 200,
                        ),
                      )
                    : Center(
                        child: Icon(
                          AppIcons.fileAudio,
                          size: 68,
                          color: colors.accentPrimary,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.bgPrimary.withValues(alpha: 0.96),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            final track = _viewModel.currentTrack;
            if (track == null) {
              return Center(
                child: Text(
                  'No audio track selected',
                  style: TextStyle(color: colors.textSecondary),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                children: [
                  // Top bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                        color: colors.textPrimary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Column(
                        children: [
                          Text(
                            'NOW PLAYING',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: colors.accentPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Track ${_viewModel.currentIndex + 1} of ${_viewModel.playlist.length}',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(AppIcons.share, size: 22),
                        color: colors.textPrimary,
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(text: track.name),
                        ),
                      ),
                    ],
                  ),

                  Expanded(
                    child: Center(
                      child: _buildArtwork(track, colors),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Track Title & Badges
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.accentPrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          track.name.contains('.')
                              ? track.name.split('.').last.toUpperCase()
                              : 'AUDIO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.accentPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '•  ${track.formattedSize}',
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Progress Scrubber Bar
                  AudioProgressBar(
                    position: _viewModel.position,
                    duration: _viewModel.duration,
                    mergedBuffered: _viewModel.mergedBuffered,
                    onSeek: _viewModel.seekTo,
                  ),

                  const SizedBox(height: 18),

                  // Transport Controls
                  AudioPlayerControls(
                    isPlaying: _viewModel.isPlaying,
                    isBuffering: _viewModel.isBuffering,
                    onTogglePlay: _viewModel.togglePlay,
                    onPrevious: _viewModel.previousTrack,
                    onNext: _viewModel.nextTrack,
                    onSkipBackward: () => _viewModel.skipBackward(),
                    onSkipForward: () => _viewModel.skipForward(),
                    canPrevious: _viewModel.currentIndex > 0 ||
                        _viewModel.repeatMode == AudioRepeatMode.all,
                    canNext: _viewModel.currentIndex < _viewModel.playlist.length - 1 ||
                        _viewModel.repeatMode == AudioRepeatMode.all,
                  ),

                  const SizedBox(height: 18),

                  // Secondary Controls (Repeat, Speed, Playlist)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(
                        icon: Icon(
                          _viewModel.repeatMode == AudioRepeatMode.one
                              ? AppIcons.repeatOne
                              : AppIcons.repeat,
                          color: _viewModel.repeatMode != AudioRepeatMode.off
                              ? colors.accentPrimary
                              : colors.textTertiary,
                        ),
                        onPressed: _viewModel.toggleRepeat,
                      ),
                      ActionChip(
                        label: Text(
                          '${_viewModel.playbackSpeed}x',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        backgroundColor: colors.bgSurfaceInset,
                        onPressed: _showSpeedSheet,
                      ),
                      IconButton(
                        icon: Icon(AppIcons.playlist, color: colors.textPrimary),
                        onPressed: _showPlaylistSheet,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
