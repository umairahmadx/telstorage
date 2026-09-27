/*
 * File: video_player_screen.dart
 * Description: Fullscreen in-app video player with gesture controls, local HTTP proxy streaming, and glassmorphic overlays.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/services/device_hardware_service.dart';
import '../../../../../../core/services/service_locator.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/dialogs/app_dialogs.dart';
import '../../../../../../shared/widgets/thumbnail_widget.dart';
import 'models/video_aspect_ratio_mode.dart';
import 'viewmodel/video_player_view_model.dart';
import 'widgets/video_audio_subtitle_sheet.dart';
import 'widgets/video_bottom_action_bar.dart';
import 'widgets/video_chunk_inspector_sheet.dart';
import 'widgets/video_drag_hud.dart';
import 'widgets/video_gesture_overlay.dart';
import 'widgets/video_player_controls_overlay.dart';
import 'widgets/video_player_top_bar.dart';
import 'widgets/video_progress_bar.dart';
import 'widgets/video_speed_dialog.dart';

/// Fullscreen video player screen supporting on-demand streaming and fast seeking.
class VideoPlayerScreen extends StatefulWidget {
  final List<FileRecord> videos;
  final int initialIndex;
  final String? heroPrefix;
  final VideoPlayerViewModel? viewModel;

  const VideoPlayerScreen({
    super.key,
    required this.videos,
    required this.initialIndex,
    this.heroPrefix,
    this.viewModel,
  });

  static void open(
    BuildContext context, {
    required List<FileRecord> videos,
    required int initialIndex,
    String? heroPrefix,
  }) {
    if (videos.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, anim1, anim2) => FadeTransition(
          opacity: anim1,
          child: VideoPlayerScreen(
            videos: videos,
            initialIndex: initialIndex.clamp(0, videos.length - 1),
            heroPrefix: heroPrefix,
          ),
        ),
      ),
    );
  }

  static bool isVideoRecord(FileRecord file) {
    final mime = file.mimeType.toLowerCase();
    if (mime.startsWith('video/')) return true;
    final name = file.name.toLowerCase();
    return name.endsWith('.mp4') ||
        name.endsWith('.mkv') ||
        name.endsWith('.webm') ||
        name.endsWith('.mov') ||
        name.endsWith('.avi') ||
        name.endsWith('.3gp') ||
        name.endsWith('.flv');
  }

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerViewModel _viewModel;
  late int _currentIndex;
  bool _isLandscape = false;
  VideoAspectRatioMode _aspectRatioMode = VideoAspectRatioMode.fit;
  final _gestureOverlayKey = GlobalKey<VideoGestureOverlayState>();

  void _toggleAspectRatio() {
    const modes = VideoAspectRatioMode.values;
    final nextIndex = (_aspectRatioMode.index + 1) % modes.length;
    final newMode = modes[nextIndex];
    setState(() => _aspectRatioMode = newMode);
    _gestureOverlayKey.currentState?.showCenterToast(
      message: newMode.label,
      icon: Icons.aspect_ratio_rounded,
    );
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Strictly manual orientation lock: initial portrait, no gyro auto-rotation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    if (ServiceLocator.instance.isInitialized) {
      ServiceLocator.instance.thumbnailRepository.pauseDownloads();
    }
    _currentIndex = widget.initialIndex;
    _viewModel = widget.viewModel ?? VideoPlayerViewModel();
    DeviceHardwareService.instance.init();
    if (widget.viewModel == null) {
      _loadCurrentVideo();
    }
  }

  void _loadCurrentVideo() {
    final file = widget.videos[_currentIndex];
    _viewModel.initialize(file);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (ServiceLocator.instance.isInitialized) {
      ServiceLocator.instance.thumbnailRepository.resumeDownloads();
    }
    DeviceHardwareService.instance.restoreDefaults();
    if (widget.viewModel == null) {
      _viewModel.dispose();
    }
    super.dispose();
  }

  void _handleSave() {
    final file = widget.videos[_currentIndex];
    if (ServiceLocator.instance.isInitialized) {
      ServiceLocator.instance.downloadFileUseCase(file);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download started for ${file.name}')),
      );
    }
  }

  void _toggleOrientation() {
    _isLandscape = !_isLandscape;
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  void _handleShare() {
    final currentFile = widget.videos[_currentIndex];
    SharePlus.instance.share(
      ShareParams(
        text: 'Sharing ${currentFile.name} from TelStorage',
      ),
    );
  }

  void _handleMoreOptions() {
    final currentFile = widget.videos[_currentIndex];
    AppDialogs.showFileDetail(
      context,
      file: currentFile,
      onShare: _handleShare,
      onDownload: _handleSave,
      onRename: () {},
      onDelete: () {
        Navigator.of(context).pop();
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final currentFile = widget.videos[_currentIndex];

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ListenableBuilder(
          listenable: _viewModel,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                // Main Video Viewport with Gestures, Brightness Dimmer & Scrub HUD
                VideoGestureOverlay(
                  key: _gestureOverlayKey,
                  viewModel: _viewModel,
                  onTap: _viewModel.toggleControls,
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: _buildVideoContent(colors, currentFile),
                    ),
                  ),
                ),

                // Scrub HUD Overlay
                VideoDragHud(
                  isVisible: _viewModel.isDragging,
                  dragDelta: _viewModel.dragDelta,
                  targetPosition: _viewModel.dragTarget,
                  totalDuration: _viewModel.duration,
                ),

                // Top Bar
                VideoPlayerTopBar(
                  file: currentFile,
                  currentIndex: _currentIndex,
                  totalCount: widget.videos.length,
                  isVisible: _viewModel.areControlsVisible,
                  onBack: () {
                    SystemChrome.setPreferredOrientations([
                      DeviceOrientation.portraitUp,
                      DeviceOrientation.portraitDown,
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]);
                    Navigator.of(context).pop();
                  },
                  onSave: _handleSave,
                  onShare: _handleShare,
                  onMore: _handleMoreOptions,
                ),

                // Controls Overlay (Play / Pause / Rewind / Fast-forward / Buffering)
                if (_viewModel.errorMessage == null)
                  VideoPlayerControlsOverlay(
                    isPlaying: _viewModel.isPlaying,
                    isBuffering: !_viewModel.isInitialized || _viewModel.isBuffering,
                    isVisible: _viewModel.areControlsVisible,
                    onPlayPause: _viewModel.togglePlay,
                    onSkipForward: () => _viewModel.skipForward(),
                    onSkipBackward: () => _viewModel.skipBackward(),
                  ),

                // Bottom Progress Bar
                if (_viewModel.errorMessage == null)
                  _buildBottomBar(colors),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoContent(AppColorsExtension colors, FileRecord currentFile) {
    if (_viewModel.errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: colors.error, size: 48),
            const SizedBox(height: 16),
            Text(
              _viewModel.errorMessage!,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadCurrentVideo,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    Widget poster = Center(
      child: ThumbnailWidget(
        file: currentFile,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
      ),
    );

    if (widget.heroPrefix != null) {
      poster = Hero(
        tag: '${widget.heroPrefix}_video_hero_${currentFile.fileId}',
        child: poster,
      );
    }

    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        poster,
        if (_viewModel.videoController != null)
          Center(
            child: Video(
              controller: _viewModel.videoController!,
              controls: NoVideoControls,
              fit: _aspectRatioMode.boxFit,
              aspectRatio: _aspectRatioMode == VideoAspectRatioMode.fit
                  ? _viewModel.naturalAspectRatio
                  : _aspectRatioMode.forcedAspectRatio,
            ),
          ),
      ],
    );
  }

  Widget _buildBottomBar(AppColorsExtension colors) {
    final currentFile = widget.videos[_currentIndex];
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      bottom: _viewModel.areControlsVisible ? 0 : -100,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 8,
          top: 12,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              colors.bgPrimary.withValues(alpha: 0.85),
              colors.bgPrimary.withValues(alpha: 0.0),
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            VideoProgressBar(
              position: _viewModel.position,
              duration: _viewModel.duration,
              buffered: _viewModel.mergedBuffered,
              onSeek: _viewModel.seekTo,
              isLandscape: _isLandscape,
              onRotate: _toggleOrientation,
            ),
            VideoBottomActionBar(
              playbackSpeed: _viewModel.playbackSpeed,
              aspectRatioMode: _aspectRatioMode,
              onSpeed: () => VideoSpeedDialog.show(
                context,
                currentSpeed: _viewModel.playbackSpeed,
                onSpeedSelected: _viewModel.setPlaybackSpeed,
              ),
              onAspectRatioToggle: _toggleAspectRatio,
              onAudioSubtitles: () => VideoAudioSubtitleSheet.show(
                context,
                videoTitle: currentFile.name,
                audioTracks: _viewModel.audioTracks,
                selectedAudioTrack: _viewModel.selectedAudioTrack,
                onAudioTrackSelected: _viewModel.setAudioTrack,
                subtitleTracks: _viewModel.subtitleTracks,
                selectedSubtitleTrack: _viewModel.selectedSubtitleTrack,
                subtitleDelay: _viewModel.subtitleDelay,
                onSubtitleTrackSelected: _viewModel.setSubtitleTrack,
                onExternalSubtitleLoaded: _viewModel.loadExternalSubtitle,
                onDelayAdjusted: _viewModel.adjustSubtitleDelay,
              ),
              cachedChunks: _viewModel.cachedChunks.length,
              totalChunks: _viewModel.totalChunks,
              cachedMb: _viewModel.cachedMb,
              totalMb: _viewModel.totalMb,
              onCacheInspector: () => VideoChunkInspectorSheet.show(
                context,
                viewModel: _viewModel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
