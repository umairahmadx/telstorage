/// File: thumbnail_widget.dart
/// Description: Component and logic definition for thumbnail_widget.dart in TelStorage.
library;

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/models/file_record.dart';
import '../../core/services/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_icons.dart';
import '../../core/utils/thumbnail_helper_native.dart'
    if (dart.library.js_interop) '../../core/utils/thumbnail_helper_web.dart';

class ThumbnailWidget extends StatefulWidget {
  final FileRecord file;
  final double width;
  final double height;
  final BoxFit fit;

  const ThumbnailWidget({
    super.key,
    required this.file,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
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
    _thumbnailFuture = ServiceLocator.instance.thumbnailRepository
        .getThumbnailData(widget.file);
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
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    // For files with uploaded thumbnails (Images, Videos, PDFs)
    if (widget.file.thumbnailFileId != null) {
      return FutureBuilder<dynamic>(
        future: _thumbnailFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            final data = snapshot.data;

            if (data == null) return _buildThumbnailerFallback(colors);

            ImageProvider imageProvider;
            if (kIsWeb && data is Uint8List) {
              imageProvider = MemoryImage(data);
            } else if (data is String) {
              final nativeProvider =
                  ThumbnailHelper.imageProviderFromPath(data);
              if (nativeProvider == null) return _buildThumbnailerFallback(colors);
              imageProvider = nativeProvider;
            } else if (data is Uint8List) {
              imageProvider = MemoryImage(data);
            } else {
              return _buildThumbnailerFallback(colors);
            }

            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image(
                image: imageProvider,
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
                errorBuilder: (_, __, ___) => _buildThumbnailerFallback(colors),
              ),
            );
          }

          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: colors.textTertiary),
              ),
            ),
          );
        },
      );
    }

    // No uploaded thumbnail -> Use thumbnailer directly
    return _buildThumbnailerFallback(colors);
  }

  Widget _buildThumbnailerFallback(AppColorsExtension colors) {
    IconData iconData = AppIcons.fileGeneric;
    Color iconColor = colors.textPrimary;
    Color iconBg = colors.bgSurfaceInset;

    if (widget.file.isPdf) {
      iconData = AppIcons.filePdf;
      iconColor = colors.filePdf;
      iconBg = colors.filePdfBg;
    } else if (widget.file.isVideo) {
      iconData = AppIcons.fileVideo;
      iconColor = colors.fileVideo;
      iconBg = colors.fileVideoBg;
    } else if (widget.file.name.endsWith('.zip') ||
        widget.file.mimeType.contains('zip') ||
        widget.file.mimeType.contains('archive')) {
      iconData = AppIcons.fileArchive;
      iconColor = colors.fileZip;
      iconBg = colors.bgSurfaceInset;
    } else if (widget.file.isImage) {
      iconData = AppIcons.fileImage;
      iconColor = colors.accentPrimary;
      iconBg = colors.bgSurfaceInset;
    }

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: iconBg,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        iconData,
        color: iconColor,
        size: (widget.width * 0.45).clamp(16.0, 40.0),
      ),
    );
  }
}
