/*
 * File: image_viewer_screen.dart
 * Description: Fullscreen in-app image viewer supporting horizontal folder swiping, progressive loading, zoom gestures, immersive mode, and swipe-to-dismiss.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/image_viewer_cache_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/dialogs/app_dialogs.dart';
import 'widgets/image_viewer_bottom_bar.dart';
import 'widgets/image_viewer_top_bar.dart';
import 'widgets/image_zoom_page.dart';

/// Fullscreen progressive image gallery viewer.
class ImageViewerScreen extends StatefulWidget {
  /// List of all viewable image files in current folder.
  final List<FileRecord> images;

  /// Index of the initially selected image.
  final int initialIndex;

  /// Constructs ImageViewerScreen.
  const ImageViewerScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  /// Opens the ImageViewerScreen with a smooth translucent route transition.
  static void open(
    BuildContext context, {
    required List<FileRecord> images,
    required int initialIndex,
  }) {
    if (images.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, anim1, anim2) => FadeTransition(
          opacity: anim1,
          child: ImageViewerScreen(
            images: images,
            initialIndex: initialIndex.clamp(0, images.length - 1),
          ),
        ),
      ),
    );
  }

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  // Immersive toolbar toggle
  bool _toolbarsVisible = true;

  // PageView physics lock when child is zoomed in
  bool _isZoomed = false;

  // Vertical drag-to-dismiss state
  double _dragOffset = 0.0;
  bool _isDragging = false;

  // Saved files tracking
  final Set<String> _savedFileIds = {};
  bool _isSaving = false;

  // Active touch pointers tracking for multi-touch pinch priority
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _prefetchAdjacent(_currentIndex);
    _checkIfCurrentFileSaved();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  FileRecord get _currentFile => widget.images[_currentIndex];

  void _prefetchAdjacent(int index) {
    final cache = ImageViewerCacheService.instance;
    if (index > 0) {
      cache.prefetchImage(widget.images[index - 1]);
    }
    if (index < widget.images.length - 1) {
      cache.prefetchImage(widget.images[index + 1]);
    }
  }

  Future<void> _checkIfCurrentFileSaved() async {
    if (!ServiceLocator.instance.isInitialized) return;
    final completed =
        ServiceLocator.instance.downloadQueue.getCompletedPath(_currentFile.fileId);
    if (completed != null && mounted) {
      setState(() {
        _savedFileIds.add(_currentFile.fileId);
      });
    }
  }

  void _handlePageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _isZoomed = false;
    });
    _prefetchAdjacent(index);
    _checkIfCurrentFileSaved();
  }

  void _toggleToolbars() {
    setState(() {
      _toolbarsVisible = !_toolbarsVisible;
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_isZoomed || _pointerCount >= 2) return;
    setState(() {
      _isDragging = true;
      _dragOffset += details.primaryDelta ?? 0.0;
    });
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed || _pointerCount >= 2) return;
    final velocity = details.primaryVelocity ?? 0.0;

    if (_dragOffset.abs() > 120 || velocity.abs() > 600) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffset = 0.0;
        _isDragging = false;
      });
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final success = await ImageViewerCacheService.instance
        .saveToDevice(_currentFile, context);
    if (mounted) {
      setState(() {
        _isSaving = false;
        if (success) {
          _savedFileIds.add(_currentFile.fileId);
        }
      });
    }
  }

  void _handleShare() {
    ImageViewerCacheService.instance.shareImage(_currentFile, context);
  }

  void _handleMoreOptions() {
    AppDialogs.showFileDetail(
      context,
      file: _currentFile,
      onShare: _handleShare,
      onDownload: _handleSave,
      onRename: () {},
      onDelete: () {
        Navigator.of(context).pop(); // Close sheet
        Navigator.of(context).pop(); // Close viewer
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dragFraction = (_dragOffset.abs() / 300.0).clamp(0.0, 1.0);
    final backdropOpacity = (1.0 - (dragFraction * 0.75)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: colors.bgPrimary.withValues(alpha: backdropOpacity),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Viewport with vertical drag-to-dismiss transform & multi-touch pinch priority
          Listener(
            onPointerDown: (_) {
              _pointerCount++;
              if (_pointerCount >= 2 && mounted) {
                setState(() {
                  _dragOffset = 0.0;
                  _isDragging = false;
                });
              }
            },
            onPointerUp: (_) {
              _pointerCount = (_pointerCount - 1).clamp(0, 10);
              if (mounted) setState(() {});
            },
            onPointerCancel: (_) {
              _pointerCount = (_pointerCount - 1).clamp(0, 10);
              if (mounted) setState(() {});
            },
            child: GestureDetector(
              onVerticalDragUpdate:
                  (_isZoomed || _pointerCount >= 2) ? null : _handleVerticalDragUpdate,
              onVerticalDragEnd:
                  (_isZoomed || _pointerCount >= 2) ? null : _handleVerticalDragEnd,
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: PageView.builder(
                  controller: _pageController,
                  physics: (_isZoomed || _pointerCount >= 2)
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  itemCount: widget.images.length,
                  onPageChanged: _handlePageChanged,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: ImageZoomPage(
                        key: ValueKey(widget.images[index].fileId),
                        file: widget.images[index],
                        onZoomChanged: (zoomed) {
                          setState(() {
                            _isZoomed = zoomed;
                            if (zoomed) _toolbarsVisible = false;
                          });
                        },
                        onToggleImmersive: _toggleToolbars,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Top Header Bar
          if (!_isDragging)
            ImageViewerTopBar(
              file: _currentFile,
              currentIndex: _currentIndex,
              totalCount: widget.images.length,
              isVisible: _toolbarsVisible,
              onBack: () => Navigator.of(context).pop(),
              onShare: _handleShare,
              onMore: _handleMoreOptions,
            ),

          // Bottom Action & Info Bar
          if (!_isDragging)
            ImageViewerBottomBar(
              file: _currentFile,
              isVisible: _toolbarsVisible,
              isSaved: _savedFileIds.contains(_currentFile.fileId),
              isSaving: _isSaving,
              onSave: _handleSave,
              onShare: _handleShare,
            ),
        ],
      ),
    );
  }
}
