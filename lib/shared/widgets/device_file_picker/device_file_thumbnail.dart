/*
 * File: device_file_thumbnail.dart
 * Description: High-performance device file thumbnail preview widget supporting direct image decoding,
 * lazy in-memory cached video and PDF previews, and fallback category icons with tap-to-open interaction.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_colors_extension.dart';
import '../../../../core/utils/thumbnail_helper_native.dart';

/// Thumbnail component for local device files in the file picker.
class DeviceFileThumbnail extends StatefulWidget {
  /// Local file system path.
  final String filePath;

  /// File name used for extension detection.
  final String fileName;

  /// Fallback icon when thumbnail is unavailable or loading.
  final IconData icon;

  /// Color for the fallback icon.
  final Color iconColor;

  /// Callback when user taps thumbnail to preview in system default app.
  final VoidCallback onOpen;

  /// Target thumbnail dimensions (width and height).
  final double size;

  /// Constructs DeviceFileThumbnail.
  const DeviceFileThumbnail({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.icon,
    required this.iconColor,
    required this.onOpen,
    this.size = 42,
  });

  @override
  State<DeviceFileThumbnail> createState() => _DeviceFileThumbnailState();
}

class _DeviceFileThumbnailState extends State<DeviceFileThumbnail> {
  static final Map<String, Uint8List> _thumbCache = {};

  @override
  void initState() {
    super.initState();
    _loadLazyThumbnail();
  }

  @override
  void didUpdateWidget(covariant DeviceFileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _loadLazyThumbnail();
    }
  }

  bool get _isImage {
    final ext = p.extension(widget.fileName).toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'}.contains(ext);
  }

  bool get _isVideo {
    final ext = p.extension(widget.fileName).toLowerCase();
    return const {'.mp4', '.mov', '.mkv', '.webm', '.avi'}.contains(ext);
  }

  bool get _isPdf {
    final ext = p.extension(widget.fileName).toLowerCase();
    return ext == '.pdf';
  }

  Future<void> _loadLazyThumbnail() async {
    if (_thumbCache.containsKey(widget.filePath)) return;

    if (_isVideo) {
      try {
        final data = await ThumbnailHelper.extractVideoThumbnailData(widget.filePath);
        if (data != null && mounted) {
          _thumbCache[widget.filePath] = data;
          setState(() {});
          return;
        }
      } catch (_) {}
    } else if (_isPdf) {
      try {
        final doc = await PdfDocument.openFile(widget.filePath);
        final page = await doc.getPage(1);
        final pageImage = await page.render(
          width: 84,
          height: (84 * (page.height / page.width)).toDouble(),
          format: PdfPageImageFormat.jpeg,
        );
        await page.close();
        await doc.close();
        if (pageImage != null && mounted) {
          _thumbCache[widget.filePath] = pageImage.bytes;
          setState(() {});
          return;
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();
    final borderRadius = BorderRadius.circular(8);

    Widget content;
    if (_isImage) {
      content = Image.file(
        File(widget.filePath),
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        cacheWidth: (widget.size * 2).toInt(),
        cacheHeight: (widget.size * 2).toInt(),
        errorBuilder: (_, __, ___) => _buildFallback(colors),
      );
    } else if ((_isVideo || _isPdf) && _thumbCache.containsKey(widget.filePath)) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            _thumbCache[widget.filePath]!,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
          ),
          if (_isVideo)
            Center(
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.white,
                  size: 14,
                ),
              ),
            ),
        ],
      );
    } else {
      content = _buildFallback(colors);
    }

    return Material(
      color: colors?.bgSurfaceInset ?? AppColors.grey800,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: widget.onOpen,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: content,
        ),
      ),
    );
  }

  Widget _buildFallback(AppColorsExtension? colors) {
    return Center(
      child: Icon(widget.icon, color: widget.iconColor, size: 22),
    );
  }
}
