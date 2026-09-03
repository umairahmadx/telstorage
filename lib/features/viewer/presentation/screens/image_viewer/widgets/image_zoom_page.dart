/*
 * File: image_zoom_page.dart
 * Description: Progressive image zoom page combining zero-latency thumbnail placeholder, background full-res cache loader, and interactive pan/zoom gestures.
 */

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/image_viewer_cache_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/core/utils/thumbnail_helper_native.dart'
    if (dart.library.js_interop) 'package:telstorage/core/utils/thumbnail_helper_web.dart';

/// Single page widget inside ImageViewerScreen managing progressive loading and pan/zoom gestures.
class ImageZoomPage extends StatefulWidget {
  /// Associated FileRecord data model.
  final FileRecord file;

  /// Callback when zoom scale changes (used to lock PageView physics when zoomed).
  final ValueChanged<bool> onZoomChanged;

  /// Callback to toggle immersive toolbar visibility on single tap.
  final VoidCallback onToggleImmersive;

  /// Constructs ImageZoomPage.
  const ImageZoomPage({
    super.key,
    required this.file,
    required this.onZoomChanged,
    required this.onToggleImmersive,
  });

  @override
  State<ImageZoomPage> createState() => _ImageZoomPageState();
}

class _ImageZoomPageState extends State<ImageZoomPage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformationController =
      TransformationController();
  late final AnimationController _animationController;
  Animation<Matrix4>? _zoomAnimation;

  TapDownDetails? _doubleTapDetails;
  bool _isZoomed = false;

  // Progressive image state
  File? _cachedFullFile;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusText = '';

  // Thumbnail fallback data
  Uint8List? _thumbBytes;
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transformationController.value = _zoomAnimation!.value;
        }
      });

    _transformationController.addListener(_handleTransformationChange);
    _initThumbnail();
    _loadFullResolutionImage();
  }

  @override
  void didUpdateWidget(covariant ImageZoomPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.fileId != widget.file.fileId) {
      _resetZoom();
      _initThumbnail();
      _loadFullResolutionImage();
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_handleTransformationChange);
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _handleTransformationChange() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final isZoomed = scale > 1.05;
    if (isZoomed != _isZoomed) {
      _isZoomed = isZoomed;
      widget.onZoomChanged(isZoomed);
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
    _isZoomed = false;
    widget.onZoomChanged(false);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final begin = _transformationController.value;
    final Matrix4 end;

    if (currentScale > 1.05) {
      // Zoom out to normal
      end = Matrix4.identity();
    } else {
      // Zoom in to 2.5x centered at tap location
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      end = Matrix4.identity()
        ..translateByDouble(-position.dx * 1.5, -position.dy * 1.5, 0.0, 1.0)
        ..scaleByDouble(2.5, 2.5, 1.0, 1.0);
    }

    _zoomAnimation = Matrix4Tween(begin: begin, end: end).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward(from: 0.0);
  }

  void _initThumbnail() {
    if (!ServiceLocator.instance.isInitialized) return;

    // 1. Instant LRU memory check (0ms)
    final mem = ServiceLocator.instance.thumbnailRepository
        .getMemoryCachedBytes(widget.file.fileId);
    if (mem != null) {
      _thumbBytes = mem;
      return;
    }

    // 2. Disk thumbnail check
    ThumbnailHelper.cachedThumbnailPath(widget.file.fileId).then((path) {
      if (mounted && path != null) {
        setState(() {
          _thumbPath = path;
        });
      }
    });
  }

  Future<void> _loadFullResolutionImage() async {
    final cacheService = ImageViewerCacheService.instance;

    // Step 1: Instant local cache check
    final existing = await cacheService.getCachedImageFile(widget.file);
    if (existing != null && mounted) {
      setState(() {
        _cachedFullFile = existing;
        _isDownloading = false;
      });
      return;
    }

    // Step 2: Background download
    if (mounted) {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.05;
        _statusText = 'Loading…';
      });
    }

    final downloaded = await cacheService.downloadImageToCache(
      widget.file,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            _statusText = status;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _cachedFullFile = downloaded;
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onToggleImmersive,
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Main Pan & Zoom Viewport
          InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1.0,
            maxScale: 5.0,
            clipBehavior: Clip.none,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Layer 1: Instant 0ms Thumbnail Base
                  if (_thumbBytes != null)
                    Image.memory(
                      _thumbBytes!,
                      fit: BoxFit.contain,
                    )
                  else if (_thumbPath != null && File(_thumbPath!).existsSync())
                    Image.file(
                      File(_thumbPath!),
                      fit: BoxFit.contain,
                    )
                  else
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: Center(
                        child: Icon(
                          Icons.image_outlined,
                          size: 48,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),

                  // Layer 2: Crystal-clear High-Res Image with Smooth Crossfade
                  if (_cachedFullFile != null)
                    AnimatedOpacity(
                      opacity: 1.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeIn,
                      child: Image.file(
                        _cachedFullFile!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Layer 3: Floating Non-Intrusive Download Progress Indicator
          if (_isDownloading && _cachedFullFile == null)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.bgPrimary.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colors.borderSubtle.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          value: _downloadProgress > 0 ? _downloadProgress : null,
                          strokeWidth: 2,
                          color: colors.accentPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _downloadProgress > 0.05
                            ? '${(_downloadProgress * 100).toInt()}%'
                            : _statusText,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
