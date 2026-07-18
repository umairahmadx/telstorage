import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:thumbnailer/thumbnailer.dart';

import '../../core/models/file_record.dart';
import '../../core/services/service_locator.dart';
import '../../core/utils/thumbnail_helper_native.dart'
    if (dart.library.js_interop) '../../core/utils/thumbnail_helper_web.dart';

class ThumbnailWidget extends StatefulWidget {
  final FileRecord file;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget fallback;

  const ThumbnailWidget({
    super.key,
    required this.file,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    required this.fallback,
  });

  @override
  State<ThumbnailWidget> createState() => _ThumbnailWidgetState();
}

class _ThumbnailWidgetState extends State<ThumbnailWidget> {
  late Future<dynamic> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _initThumbnail();
  }

  void _initThumbnail() {
    if (widget.file.isVideo && !kIsWeb) {
      _thumbnailFuture = _generateVideoThumbnail();
    } else {
      _thumbnailFuture = ServiceLocator.instance.thumbnailRepository
          .getThumbnailData(widget.file);
    }
  }

  Future<String?> _generateVideoThumbnail() async {
    try {
      final cachedPath =
          await ThumbnailHelper.cachedVideoThumbnailPath(widget.file.fileId);
      if (cachedPath != null) return cachedPath;

      final downloadJob = ServiceLocator.instance.downloadQueue.allJobs
          .where((j) => j.fileId == widget.file.fileId && j.isComplete)
          .firstOrNull;

      if (downloadJob?.localPath != null) {
        return ThumbnailHelper.generateVideoThumbnail(
          widget.file.fileId,
          downloadJob!.localPath!,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  void didUpdateWidget(covariant ThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.fileId != widget.file.fileId ||
        oldWidget.file.thumbnailFileId != widget.file.thumbnailFileId) {
      _initThumbnail();
    }
  }

  @override
  Widget build(BuildContext context) {
    // For documents and other non-media, use thumbnailer for branded icons
    if (!widget.file.isImage && !widget.file.isVideo) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Thumbnail(
          mimeType: widget.file.mimeType,
          widgetSize: widget.width,
          name: widget.file.name,
          onlyIcon: true,
          useWaterMark: false,
        ),
      );
    }

    // For images and videos (using Telegram provided thumbs or local generation)
    return FutureBuilder<dynamic>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          final data = snapshot.data;

          if (data == null) return widget.fallback;

          ImageProvider imageProvider;
          if (kIsWeb && data is Uint8List) {
            imageProvider = MemoryImage(data);
          } else if (data is String) {
            final nativeProvider = ThumbnailHelper.imageProviderFromPath(data);
            if (nativeProvider == null) return widget.fallback;
            imageProvider = nativeProvider;
          } else if (data is Uint8List) {
            imageProvider = MemoryImage(data);
          } else {
            return widget.fallback;
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: imageProvider,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              errorBuilder: (_, __, ___) => widget.fallback,
            ),
          );
        }

        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white24),
            ),
          ),
        );
      },
    );
  }
}
