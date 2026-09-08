/*
 * File: video_player_screen.dart
 * Description: Fullscreen in-app video player with gesture controls, local HTTP proxy streaming, and glassmorphic overlays.
 */

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/services/service_locator.dart';
import '../../../../../../core/theme/app_theme.dart';
import 'viewmodel/video_player_view_model.dart';
import 'widgets/video_player_controls_overlay.dart';
import 'widgets/video_player_top_bar.dart';
import 'widgets/video_progress_bar.dart';

/// Fullscreen video player screen supporting on-demand streaming and fast seeking.
class VideoPlayerScreen extends StatefulWidget {
  /// List of viewable video files in current folder.
  final List<FileRecord> videos;

  /// Index of initially selected video.
  final int initialIndex;

  /// Constructs VideoPlayerScreen.
  const VideoPlayerScreen({
    super.key,
    required this.videos,
    required this.initialIndex,
  });

  /// Opens VideoPlayerScreen with a smooth translucent route transition.
  static void open(
    BuildContext context, {
    required List<FileRecord> videos,
    required int initialIndex,
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
          ),
        ),
      ),
    );
  }

  /// Checks if a given FileRecord represents a playable video file.
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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _viewModel = VideoPlayerViewModel();
    _loadCurrentVideo();
  }

  void _loadCurrentVideo() {
    final file = widget.videos[_currentIndex];
    _viewModel.initialize(file);
  }

  @override
  void dispose() {
    _viewModel.dispose();
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final currentFile = widget.videos[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _viewModel,
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Main Video Viewport & Tap Detectors
              GestureDetector(
                onTap: _viewModel.toggleControls,
                onDoubleTapDown: (details) {
                  final screenWidth = MediaQuery.sizeOf(context).width;
                  if (details.localPosition.dx < screenWidth / 2) {
                    _viewModel.skipBackward();
                  } else {
                    _viewModel.skipForward();
                  }
                },
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: _buildVideoContent(colors),
                  ),
                ),
              ),

              // Top Bar
              VideoPlayerTopBar(
                file: currentFile,
                currentIndex: _currentIndex,
                totalCount: widget.videos.length,
                isVisible: _viewModel.areControlsVisible,
                onBack: () => Navigator.of(context).pop(),
                onSave: _handleSave,
              ),

              // Controls Overlay (Play / Pause / Rewind / Fast-forward)
              if (_viewModel.isInitialized && _viewModel.errorMessage == null)
                VideoPlayerControlsOverlay(
                  isPlaying: _viewModel.isPlaying,
                  isBuffering: _viewModel.isBuffering,
                  isVisible: _viewModel.areControlsVisible,
                  onPlayPause: _viewModel.togglePlay,
                  onSkipForward: () => _viewModel.skipForward(),
                  onSkipBackward: () => _viewModel.skipBackward(),
                ),

              // Bottom Progress Bar
              if (_viewModel.isInitialized && _viewModel.errorMessage == null)
                _buildBottomBar(colors),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideoContent(AppColorsExtension colors) {
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

    if (!_viewModel.isInitialized || _viewModel.controller == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
          ),
          const SizedBox(height: 16),
          Text(
            'Starting streaming proxy…',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ],
      );
    }

    return AspectRatio(
      aspectRatio: _viewModel.controller!.value.aspectRatio,
      child: VideoPlayer(_viewModel.controller!),
    );
  }

  Widget _buildBottomBar(AppColorsExtension colors) {
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
        child: VideoProgressBar(
          position: _viewModel.position,
          duration: _viewModel.duration,
          buffered: _viewModel.buffered,
          onSeek: _viewModel.seekTo,
        ),
      ),
    );
  }
}
