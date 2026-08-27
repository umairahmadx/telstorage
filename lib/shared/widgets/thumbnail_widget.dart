/*
 * File: thumbnail_widget.dart
 * Description: Renders high-res 400px WebP media previews with universal smart extension badging and zero-extension fallbacks.
 */

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/models/file_record.dart';
import '../../core/services/service_locator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_icons.dart';
import '../../core/utils/thumbnail_helper_native.dart'
    if (dart.library.js_interop) '../../core/utils/thumbnail_helper_web.dart';

/// Helper utility resolving smart badge label, icon, and colors for any file.
class SmartBadgeInfo {
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;

  const SmartBadgeInfo({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
  });

  /// Resolves the smart badge info based on filename and mimeType.
  static SmartBadgeInfo resolve(
      String filename, String mimeType, AppColorsExtension colors) {
    final mime = mimeType.toLowerCase();
    String badgeLabel = '';
    IconData iconData = AppIcons.fileGeneric;
    Color iconColor = colors.textPrimary;
    Color iconBg = colors.bgSurfaceInset;

    // 1. Extract file extension from filename if present
    if (filename.contains('.')) {
      final parts = filename.split('.');
      final rawExt = parts.last.toUpperCase();
      if (rawExt.isNotEmpty && rawExt.length <= 6) {
        badgeLabel = rawExt;
      }
    }

    // 2. Special filename resolution when no extension is present
    if (badgeLabel.isEmpty) {
      final upperName = filename.toUpperCase();
      if (upperName == 'DOCKERFILE' || upperName.startsWith('DOCKERFILE.')) {
        badgeLabel = 'DOCKER';
        iconData = Icons.developer_board_rounded;
        iconColor = colors.accentPrimary;
      } else if (upperName == 'MAKEFILE' ||
          upperName == 'CMAKE' ||
          upperName == 'GEMFILE') {
        badgeLabel = 'MAKE';
        iconData = Icons.build_rounded;
        iconColor = colors.fileZip;
      } else if (upperName == 'LICENSE' ||
          upperName == 'README' ||
          upperName.startsWith('README.')) {
        badgeLabel = 'DOC';
        iconData = AppIcons.fileGeneric;
        iconColor = colors.textPrimary;
      } else if (mime.startsWith('text/')) {
        badgeLabel = 'TXT';
        iconData = Icons.text_snippet_outlined;
        iconColor = colors.accentPrimary;
      } else if (mime.startsWith('audio/')) {
        badgeLabel = 'AUDIO';
        iconData = Icons.music_note_rounded;
        iconColor = colors.fileVideo;
      } else if (mime.startsWith('image/')) {
        badgeLabel = 'IMG';
        iconData = AppIcons.fileImage;
        iconColor = colors.accentPrimary;
      } else if (mime.startsWith('video/')) {
        badgeLabel = 'VIDEO';
        iconData = AppIcons.fileVideo;
        iconColor = colors.fileVideo;
      } else {
        badgeLabel = 'FILE';
        iconData = AppIcons.fileGeneric;
        iconColor = colors.textSecondary;
      }
    } else {
      // 3. Color-code and assign icons for recognized extensions
      if (badgeLabel == 'PDF') {
        iconData = AppIcons.filePdf;
        iconColor = colors.filePdf;
        iconBg = colors.filePdfBg;
      } else if ({'MP4', 'MKV', 'MOV', 'AVI', 'WEBM', 'FLV', '3GP', 'M4V'}
          .contains(badgeLabel)) {
        iconData = AppIcons.fileVideo;
        iconColor = colors.fileVideo;
        iconBg = colors.fileVideoBg;
      } else if ({'PNG', 'JPG', 'JPEG', 'WEBP', 'GIF', 'SVG', 'BMP', 'HEIC'}
          .contains(badgeLabel)) {
        iconData = AppIcons.fileImage;
        iconColor = colors.accentPrimary;
        iconBg = colors.bgSurfaceInset;
      } else if ({'ZIP', 'RAR', '7Z', 'TAR', 'GZ', 'BZ2', 'XZ'}
          .contains(badgeLabel)) {
        iconData = AppIcons.fileArchive;
        iconColor = colors.fileZip;
        iconBg = colors.bgSurfaceInset;
      } else if ({'MP3', 'FLAC', 'WAV', 'AAC', 'M4A', 'OGG', 'OPUS'}
          .contains(badgeLabel)) {
        iconData = Icons.music_note_rounded;
        iconColor = colors.fileVideo;
        iconBg = colors.bgSurfaceInset;
      } else if ({'APK', 'AAB', 'EXE', 'DMG', 'DEB', 'RPM', 'MSI'}
          .contains(badgeLabel)) {
        iconData = Icons.android_rounded;
        iconColor = colors.success;
        iconBg = colors.bgSurfaceInset;
      } else if ({
        'DART',
        'JS',
        'TS',
        'PY',
        'JSON',
        'HTML',
        'CSS',
        'CPP',
        'JAVA',
        'KT',
        'RS',
        'GO',
        'SH'
      }.contains(badgeLabel)) {
        iconData = Icons.code_rounded;
        iconColor = colors.accentPrimary;
        iconBg = colors.bgSurfaceInset;
      } else if ({'DOCX', 'DOC', 'XLSX', 'XLS', 'PPTX', 'PPT', 'CSV'}
          .contains(badgeLabel)) {
        iconData = Icons.description_outlined;
        iconColor = colors.textPrimary;
        iconBg = colors.bgSurfaceInset;
      }
    }

    return SmartBadgeInfo(
      label: badgeLabel,
      icon: iconData,
      iconColor: iconColor,
      bgColor: iconBg,
    );
  }
}

/// Widget displaying 400px WebP media thumbnails with smart universal fallback badging.
class ThumbnailWidget extends StatefulWidget {
  /// FileRecord metadata containing fileId and thumbnailFileId.
  final FileRecord file;

  /// Target display width.
  final double width;

  /// Target display height.
  final double height;

  /// Target image fit mode.
  final BoxFit fit;

  /// Constructs ThumbnailWidget.
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
    try {
      _thumbnailFuture = ServiceLocator.instance.thumbnailRepository
          .getThumbnailData(widget.file);
    } catch (_) {
      _thumbnailFuture = Future<dynamic>.value(null);
    }
  }

  @override
  void didUpdateWidget(covariant ThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.fileId != widget.file.fileId ||
        oldWidget.file.thumbnailFileId != widget.file.thumbnailFileId) {
      setState(() {
        _initThumbnail();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    // 1. Instant Synchronous LRU Memory Hit (0ms latency, zero flicker)
    Uint8List? memoryBytes;
    try {
      memoryBytes = ServiceLocator.instance.thumbnailRepository
          .getMemoryCachedBytes(widget.file.fileId);
    } catch (_) {}

    if (memoryBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          memoryBytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          errorBuilder: (_, __, ___) => _buildThumbnailerFallback(colors),
        ),
      );
    }

    // 2. For files with uploaded thumbnails (Async path)
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
              if (nativeProvider == null) {
                return _buildThumbnailerFallback(colors);
              }
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

    // No uploaded thumbnail -> Use universal smart badge fallback
    return _buildThumbnailerFallback(colors);
  }

  Widget _buildThumbnailerFallback(AppColorsExtension colors) {
    final badge =
        SmartBadgeInfo.resolve(widget.file.name, widget.file.mimeType, colors);

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: badge.bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderSubtle, width: 1),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            badge.icon,
            color: badge.iconColor.withAlpha(210),
            size: (widget.width * 0.40).clamp(16.0, 36.0),
          ),
          if (badge.label.isNotEmpty && widget.width >= 40)
            Positioned(
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.bgSurface.withAlpha(230),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.borderSubtle, width: 0.5),
                ),
                child: Text(
                  badge.label,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    color: badge.iconColor,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
