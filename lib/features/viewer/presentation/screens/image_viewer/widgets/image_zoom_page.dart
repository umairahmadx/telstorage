/*
 * File: image_zoom_page.dart
 * Description: Progressive image zoom page combining zero-latency thumbnail placeholder, background full-res cache loader, and priority scheduling.
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

/// Single page widget inside ImageViewerScreen managing progressive image loading.
class ImageZoomPage extends StatefulWidget {
  /// Associated FileRecord data model.
  final FileRecord file;

  /// Whether this page is the currently active visible page.
  final bool isActive;

  /// Callback when zoom scale changes (handled by PhotoViewGallery).
  final ValueChanged<bool>? onZoomChanged;

  /// Callback to toggle immersive toolbar visibility on single tap.
  final VoidCallback? onToggleImmersive;

  /// Constructs ImageZoomPage.
  const ImageZoomPage({
    super.key,
    required this.file,
    this.isActive = true,
    this.onZoomChanged,
    this.onToggleImmersive,
  });

  @override
  State<ImageZoomPage> createState() => _ImageZoomPageState();
}

class _ImageZoomPageState extends State<ImageZoomPage> {
  // Progressive image state
  File? _cachedFullFile;
  bool _isDownloading = false;

  // Thumbnail fallback data
  Uint8List? _thumbBytes;
  String? _thumbPath;

  @override
  void initState() {
    super.initState();
    _initThumbnail();
    _loadFullResolutionImage();
  }

  @override
  void didUpdateWidget(covariant ImageZoomPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.fileId != widget.file.fileId) {
      _initThumbnail();
      _loadFullResolutionImage();
    } else if (widget.isActive && !oldWidget.isActive) {
      // Prioritize active image download if not yet loaded
      if (_cachedFullFile == null) {
        _loadFullResolutionImage();
      }
    }
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
      } else if (mounted && widget.file.thumbnailFileId != null) {
        // 3. Priority network thumbnail fetch if active
        ServiceLocator.instance.thumbnailRepository
            .getThumbnailData(widget.file, isPriority: widget.isActive)
            .then((data) {
          if (mounted && data != null) {
            setState(() {
              if (data is Uint8List) {
                _thumbBytes = data;
              } else if (data is String) {
                _thumbPath = data;
              }
            });
          }
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

    // Step 2: Download with priority scheduling
    if (mounted) {
      setState(() {
        _isDownloading = true;
      });
    }

    final downloaded = await cacheService.downloadImageToCache(
      widget.file,
      isPriority: widget.isActive,
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
      child: Center(
        child: _cachedFullFile != null
            ? Image.file(
                _cachedFullFile!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            : Stack(
                alignment: Alignment.center,
                children: [
                  if (_thumbBytes != null)
                    Image.memory(
                      _thumbBytes!,
                      fit: BoxFit.contain,
                    )
                  else if (_thumbPath != null &&
                      File(_thumbPath!).existsSync())
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
                  if (_isDownloading)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colors.bgPrimary.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: colors.accentPrimary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
