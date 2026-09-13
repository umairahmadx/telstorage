/*
 * File: video_player_screen.dart
 * Description: Fullscreen in-app video player with gesture controls, local HTTP proxy streaming, and glassmorphic overlays.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/services/service_locator.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/dialogs/app_dialogs.dart';
import '../../../../../../shared/widgets/thumbnail_widget.dart';
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

  /// Optional prefix to namespace Hero transition tag.
  final String? heroPrefix;

  /// Optional injected ViewModel for testing or pre-configured state.
  final VideoPlayerViewModel? viewModel;

  /// Constructs VideoPlayerScreen.
  const VideoPlayerScreen({
    super.key,
    required this.videos,
    required this.initialIndex,
    this.heroPrefix,
    this.viewModel,
  });

  /// Opens VideoPlayerScreen with a smooth translucent route transition.
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
    // Allow dynamic auto-rotation (portrait + landscape) while playing video
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (ServiceLocator.instance.isInitialized) {
      ServiceLocator.instance.thumbnailRepository.pauseDownloads();
    }
    _currentIndex = widget.initialIndex;
    _viewModel = widget.viewModel ?? VideoPlayerViewModel();
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
    // Restore global portrait lock when leaving video player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    if (ServiceLocator.instance.isInitialized) {
      ServiceLocator.instance.thumbnailRepository.resumeDownloads();
    }
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
    final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    if (isPortrait) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    // Re-enable all orientations after brief delay so sensor auto-rotate remains fluid
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    });
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
        Navigator.of(context).pop(); // Close sheet
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        Navigator.of(context).pop(); // Close viewer
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
                      child: _buildVideoContent(colors, currentFile),
                    ),
                  ),
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
                    ]);
                    Navigator.of(context).pop();
                  },
                  onSave: _handleSave,
                  onRotate: _toggleOrientation,
                  onShare: _handleShare,
                  onMore: _handleMoreOptions,
                ),

                // Controls Overlay (Play / Pause / Rewind / Fast-forward / Buffering)
                if (_viewModel.errorMessage == null)
                  VideoPlayerControlsOverlay(
                    isPlaying: _viewModel.isPlaying,
                    isBuffering:
                        !_viewModel.isInitialized || _viewModel.isBuffering,
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
        // 1. Poster thumbnail immediately visible
        poster,

        // 2. Active video frame playback once initialized
        if (_viewModel.isInitialized && _viewModel.controller != null)
          Center(
            child: AspectRatio(
              aspectRatio: _viewModel.controller!.value.aspectRatio,
              child: VideoPlayer(_viewModel.controller!),
            ),
          ),
      ],
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
