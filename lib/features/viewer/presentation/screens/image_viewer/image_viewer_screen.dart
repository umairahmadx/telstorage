/*
 * File: image_viewer_screen.dart
 * Description: Fullscreen in-app image viewer supporting horizontal folder swiping, progressive loading, zoom gestures, immersive mode, and swipe-to-dismiss.
 */

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/image_viewer_cache_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/dialogs/app_dialogs.dart';
import 'widgets/dominant_vertical_drag_gesture_recognizer.dart';
import 'widgets/image_viewer_bottom_bar.dart';
import 'widgets/image_viewer_top_bar.dart';
import 'widgets/image_zoom_page.dart';
import 'widgets/responsive_page_scroll_physics.dart';

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

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with TickerProviderStateMixin {
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

  // Track page where drag started for responsive threshold snapping
  double? _dragStartPage;

  // Per-page photo view controllers to handle programmatic zoom
  final Map<int, PhotoViewController> _photoControllers = {};

  // Animation controller for smooth double-tap zoom
  late final AnimationController _zoomAnimationController;
  Animation<double>? _zoomScaleAnimation;
  Animation<Offset>? _zoomPositionAnimation;
  PhotoViewController? _animatingController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(_handleZoomAnimationTick);
    _prefetchAdjacent(_currentIndex);
    _checkIfCurrentFileSaved();
  }

  void _handleZoomAnimationTick() {
    final controller = _animatingController;
    if (controller != null) {
      final scale = _zoomScaleAnimation?.value;
      final pos = _zoomPositionAnimation?.value;
      if (scale != null) controller.scale = scale;
      if (pos != null) controller.position = pos;
    }
  }

  @override
  void dispose() {
    _zoomAnimationController.dispose();
    for (final controller in _photoControllers.values) {
      controller.dispose();
    }
    _photoControllers.clear();
    _pageController.dispose();
    super.dispose();
  }

  FileRecord get _currentFile => widget.images[_currentIndex];

  PhotoViewController _getPhotoViewController(int index) {
    return _photoControllers.putIfAbsent(index, () {
      final controller = PhotoViewController();
      controller.outputStateStream.listen((value) {
        if (index == _currentIndex && !_zoomAnimationController.isAnimating) {
          final isZoomed = (value.scale ?? 1.0) > 1.05;
          if (isZoomed != _isZoomed && mounted) {
            setState(() {
              _isZoomed = isZoomed;
              if (isZoomed) {
                _toolbarsVisible = false;
              }
            });
          }
        }
      });
      return controller;
    });
  }

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
    if (_currentIndex != index) {
      _photoControllers[_currentIndex]?.reset();
    }
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

  void _handleScaleStateChanged(PhotoViewScaleState scaleState) {
    // Only lock horizontal gestures when zoomed in, never when zoomed out
    final isZoomed = scaleState == PhotoViewScaleState.zoomedIn;
    if (isZoomed != _isZoomed) {
      setState(() {
        _isZoomed = isZoomed;
        if (isZoomed) {
          _toolbarsVisible = false;
        }
      });
    }
  }

  void _handleDoubleTap(TapDownDetails details, PhotoViewController controller) {
    if (_zoomAnimationController.isAnimating) return;

    final currentScale = controller.scale ?? 1.0;
    final currentPosition = controller.position;
    final screenSize = MediaQuery.of(context).size;

    final double targetScale;
    final Offset targetPosition;

    if (currentScale > 1.05) {
      // Zoom out to 1.0x centered
      targetScale = 1.0;
      targetPosition = Offset.zero;
    } else {
      // Zoom in to 2.5x focused on tapped focal point
      targetScale = 2.5;
      final dx = details.localPosition.dx - (screenSize.width / 2.0);
      final dy = details.localPosition.dy - (screenSize.height / 2.0);

      final computedWidth = screenSize.width * targetScale;
      final computedHeight = screenSize.height * targetScale;
      final maxPanX = (computedWidth - screenSize.width) / 2.0;
      final maxPanY = (computedHeight - screenSize.height) / 2.0;

      final targetX = (-dx * (targetScale - 1.0)).clamp(-maxPanX, maxPanX);
      final targetY = (-dy * (targetScale - 1.0)).clamp(-maxPanY, maxPanY);
      targetPosition = Offset(targetX, targetY);
    }

    _animatingController = controller;
    final curve = CurvedAnimation(
      parent: _zoomAnimationController,
      curve: Curves.easeInOutCubic,
    );
    _zoomScaleAnimation = Tween<double>(
      begin: currentScale,
      end: targetScale,
    ).animate(curve);
    _zoomPositionAnimation = Tween<Offset>(
      begin: currentPosition,
      end: targetPosition,
    ).animate(curve);

    _zoomAnimationController.forward(from: 0.0).then((_) {
      final isZoomed = targetScale > 1.05;
      if (mounted) {
        setState(() {
          _isZoomed = isZoomed;
          if (isZoomed) {
            _toolbarsVisible = false;
          }
        });
      }
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
            child: RawGestureDetector(
              gestures: {
                DominantVerticalDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        DominantVerticalDragGestureRecognizer>(
                  () => DominantVerticalDragGestureRecognizer(),
                  (instance) {
                    instance
                      ..onUpdate = (_isZoomed || _pointerCount >= 2)
                          ? null
                          : _handleVerticalDragUpdate
                      ..onEnd = (_isZoomed || _pointerCount >= 2)
                          ? null
                          : _handleVerticalDragEnd;
                  },
                ),
              },
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification) {
                      _dragStartPage = _pageController.page?.roundToDouble() ??
                          _currentIndex.toDouble();
                    }
                    return false;
                  },
                  child: PhotoViewGallery.builder(
                    pageController: _pageController,
                    pageSnapping: false,
                    scrollPhysics: (_isZoomed || _pointerCount >= 2)
                        ? const NeverScrollableScrollPhysics()
                        : ResponsivePageScrollPhysics(
                            parent: const BouncingScrollPhysics(),
                            getDragStartPage: () => _dragStartPage,
                          ),
                    itemCount: widget.images.length,
                    onPageChanged: _handlePageChanged,
                    scaleStateChangedCallback: _handleScaleStateChanged,
                    backgroundDecoration:
                        const BoxDecoration(color: Colors.transparent),
                    builder: (context, index) {
                      final file = widget.images[index];
                      final controller = _getPhotoViewController(index);
                      return PhotoViewGalleryPageOptions.customChild(
                        controller: controller,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: ImageZoomPage(
                            key: ValueKey(file.fileId),
                            file: file,
                            isActive: index == _currentIndex,
                            onToggleImmersive: _toggleToolbars,
                            onDoubleTap: (details) =>
                                _handleDoubleTap(details, controller),
                          ),
                        ),
                        childSize: MediaQuery.of(context).size,
                        initialScale: PhotoViewComputedScale.contained,
                        minScale: PhotoViewComputedScale.contained,
                        maxScale: PhotoViewComputedScale.covered * 3.5,
                        heroAttributes: PhotoViewHeroAttributes(
                          tag: 'image_hero_${file.fileId}',
                        ),
                      );
                    },
                  ),
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
