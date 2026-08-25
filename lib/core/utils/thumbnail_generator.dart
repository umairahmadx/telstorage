/*
 * File: thumbnail_generator.dart
 * Description: Generates 400px high-efficiency media previews compressed to <= 50KB for images, videos, PDFs, APKs, and code/text files.
 */

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;
import 'package:archive/archive.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:pdfx/pdfx.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../utils/app_logger.dart';

import 'thumbnail_helper_native.dart'
    if (dart.library.js_interop) 'thumbnail_helper_web.dart';

Uint8List _isolateProcessImage(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      final resized = img.copyResize(
        decoded,
        width: ThumbnailGenerator.maxDimension,
        height: ThumbnailGenerator.maxDimension,
      );
      final encoded = Uint8List.fromList(
        img.encodeJpg(resized, quality: ThumbnailGenerator.quality),
      );
      return ThumbnailGenerator.compressUnder50KB(encoded);
    }
  } catch (_) {}
  return bytes;
}

/// Holds compressed thumbnail bytes and file format extension.
class ThumbnailResult {
  /// Binary payload of the compressed thumbnail.
  final Uint8List bytes;

  /// Target file extension (e.g. 'webp' or 'jpg').
  final String extension;

  /// Constructs ThumbnailResult.
  const ThumbnailResult(this.bytes, this.extension);
}

/// Central generator creating 400px previews compressed to <= 50KB.
class ThumbnailGenerator {
  /// Maximum width/height dimension for generated thumbnails (400px).
  static const int maxDimension = AppConstants.thumbnailMaxDimension;

  /// Default compression quality percentage (80%).
  static const int quality = AppConstants.thumbnailQuality;

  /// Strict 50 KB ceiling limit for thumbnail file sizes.
  static const int maxByteSize = AppConstants.thumbnailMaxByteSize;

  /// Supported code and text extensions for canvas snippet previews.
  static const Set<String> codeExtensions = {
    'dart', 'json', 'txt', 'md', 'py', 'js', 'ts', 'html', 'css',
    'yaml', 'yml', 'xml', 'log', 'sh', 'sql', 'cpp', 'c', 'h', 'java', 'kt', 'rs',
  };

  /// Ensures thumbnail binary output is strictly under 50KB using iterative step-down.
  static Uint8List compressUnder50KB(Uint8List rawBytes) {
    if (rawBytes.length <= maxByteSize) return rawBytes;
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        int q = quality;
        int dim = maxDimension;
        while (dim >= 100) {
          final resized = img.copyResize(
            decoded,
            width: dim,
            height: dim,
          );
          final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: q));
          if (encoded.length <= maxByteSize) return encoded;
          if (q > 30) {
            q -= 15;
          } else {
            dim -= 50;
            q = 75;
          }
        }
      }
    } catch (_) {}
    return rawBytes;
  }

  /// Generates a 400px thumbnail with max 50KB size for the given file data.
  static Future<ThumbnailResult?> generate({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    try {
      Uint8List? thumbBytes;
      String ext = 'webp';
      final lowerName = filename.toLowerCase();
      final fileExt = lowerName.contains('.') ? lowerName.split('.').last : '';

      if (mimeType.startsWith('image/')) {
        thumbBytes = await generateImageThumbnail(bytes);
        ext = 'jpg';
      } else if (mimeType.startsWith('video/')) {
        thumbBytes = await generateVideoThumbnail(bytes, filename);
        ext = 'webp';
      } else if (mimeType == 'application/pdf' || fileExt == 'pdf') {
        thumbBytes = await generatePdfThumbnail(bytes);
        ext = 'jpg';
      } else if (fileExt == 'apk' || mimeType.contains('android.package-archive')) {
        thumbBytes = await generateApkThumbnail(bytes);
        ext = 'jpg';
      } else if (codeExtensions.contains(fileExt) ||
          mimeType.startsWith('text/') ||
          mimeType.contains('json') ||
          mimeType.contains('javascript')) {
        thumbBytes = await generateCodeThumbnail(bytes, filename);
        ext = 'jpg';
      }

      if (thumbBytes != null) {
        final compressedBytes = compressUnder50KB(thumbBytes);
        return ThumbnailResult(compressedBytes, ext);
      }
    } catch (e) {
      AppLogger.w('Thumbnail generation failed for $filename ($mimeType): $e',
          tag: 'ThumbnailGenerator');
    }
    return null;
  }

  /// Generates image thumbnail scaled to max 400px at 80% quality.
  static Future<Uint8List> generateImageThumbnail(Uint8List bytes) async {
    try {
      return await compute(_isolateProcessImage, bytes);
    } catch (_) {}

    final ui.Codec codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: maxDimension,
    );
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ui.Image image = fi.image;
    final ByteData? byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    if (byteData == null) throw Exception('Failed to generate image thumbnail');
    final decoded = img.decodeImage(byteData.buffer.asUint8List());
    if (decoded != null) {
      return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    }
    return byteData.buffer.asUint8List();
  }

  /// Extracts WebP video frame thumbnail scaled to max 400px at 80% quality.
  static Future<Uint8List> generateVideoThumbnail(
    Uint8List videoBytes,
    String filename,
  ) async {
    final sourcePath =
        await ThumbnailHelper.prepareVideoSource(videoBytes, filename);
    try {
      final uint8list = await VideoThumbnail.thumbnailData(
        video: sourcePath,
        imageFormat: ImageFormat.WEBP,
        maxWidth: maxDimension,
        quality: quality,
      );
      return uint8list;
    } finally {
      ThumbnailHelper.cleanVideoSource(sourcePath);
    }
  }

  /// Renders PDF first-page preview scaled to max 400px at 80% quality.
  static Future<Uint8List> generatePdfThumbnail(Uint8List pdfBytes) async {
    final document = await PdfDocument.openData(pdfBytes);
    final page = await document.getPage(1);
    final pageImage = await page.render(
      width: maxDimension.toDouble(),
      height: (maxDimension * (page.height / page.width)).toDouble(),
      format: PdfPageImageFormat.png,
    );
    await page.close();
    await document.close();
    if (pageImage == null) throw Exception('Failed to render PDF page');
    final decoded = img.decodeImage(pageImage.bytes);
    if (decoded != null) {
      return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
    }
    return pageImage.bytes;
  }

  /// Extracts the launcher icon from an Android APK archive in memory without disk writes.
  static Future<Uint8List?> generateApkThumbnail(Uint8List apkBytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(apkBytes, verify: false);
      ArchiveFile? bestIcon;
      int bestRank = -1;

      for (final file in archive) {
        if (!file.isFile) continue;
        final path = file.name.toLowerCase();
        if (path.endsWith('.png') || path.endsWith('.webp')) {
          if (path.contains('mipmap-xxxhdpi') && path.contains('ic_launcher')) {
            bestIcon = file;
            bestRank = 5;
          } else if (path.contains('mipmap-xxhdpi') && path.contains('ic_launcher') && bestRank < 4) {
            bestIcon = file;
            bestRank = 4;
          } else if (path.contains('mipmap-xhdpi') && path.contains('ic_launcher') && bestRank < 3) {
            bestIcon = file;
            bestRank = 3;
          } else if (path.contains('ic_launcher') && bestRank < 2) {
            bestIcon = file;
            bestRank = 2;
          } else if ((path.contains('icon') || path.contains('logo')) && bestRank < 1) {
            bestIcon = file;
            bestRank = 1;
          }
        }
      }

      if (bestIcon != null) {
        final iconRaw = bestIcon.content as List<int>;
        return await generateImageThumbnail(Uint8List.fromList(iconRaw));
      }
    } catch (e) {
      AppLogger.d('APK icon extraction skipped: $e', tag: 'ThumbnailGenerator');
    }
    return null;
  }

  /// Renders a 400px dark-mode code snippet preview card with line numbers and file header.
  static Future<Uint8List?> generateCodeThumbnail(
    Uint8List textBytes,
    String filename,
  ) async {
    try {
      if (textBytes.isEmpty) return null;
      final maxLen = textBytes.length > 2048 ? 2048 : textBytes.length;
      final rawStr = utf8.decode(textBytes.sublist(0, maxLen), allowMalformed: true);
      final lines = rawStr.split('\n').take(12).toList();
      if (lines.isEmpty || lines.every((l) => l.trim().isEmpty)) return null;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 400, 400));

      // Background Card
      final bgPaint = Paint()..color = AppColors.codeCanvasBg;
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 400, 400), const Radius.circular(28)),
        bgPaint,
      );

      // Header Bar
      final headerPaint = Paint()..color = AppColors.codeCanvasHeader;
      canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 400, 48), const Radius.circular(28)),
        headerPaint,
      );

      // Mac-like traffic dots
      canvas.drawCircle(const Offset(24, 24), 5, Paint()..color = AppColors.codeCanvasDotRed);
      canvas.drawCircle(const Offset(40, 24), 5, Paint()..color = AppColors.codeCanvasDotYellow);
      canvas.drawCircle(const Offset(56, 24), 5, Paint()..color = AppColors.codeCanvasDotGreen);

      // Header Filename
      final titleBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: TextAlign.right, fontSize: 13, maxLines: 1),
      )
        ..pushStyle(ui.TextStyle(color: AppColors.codeCanvasTextSecondary, fontWeight: FontWeight.bold))
        ..addText(filename);
      final titleParagraph = titleBuilder.build()..layout(const ui.ParagraphConstraints(width: 300));
      canvas.drawParagraph(titleParagraph, const Offset(80, 16));

      // Code Lines with Line Numbers
      double yOffset = 64;
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        final lineNum = '${i + 1}'.padLeft(2, ' ');
        final lineBuilder = ui.ParagraphBuilder(
          ui.ParagraphStyle(fontSize: 12, maxLines: 1),
        )
          ..pushStyle(ui.TextStyle(color: AppColors.codeCanvasLineNumber))
          ..addText('$lineNum  ')
          ..pushStyle(ui.TextStyle(color: AppColors.codeCanvasTextPrimary))
          ..addText(line.length > 35 ? '${line.substring(0, 35)}…' : line);

        final lineParagraph = lineBuilder.build()..layout(const ui.ParagraphConstraints(width: 360));
        canvas.drawParagraph(lineParagraph, Offset(18, yOffset));
        yOffset += 24;
      }

      final picture = recorder.endRecording();
      final renderedImage = await picture.toImage(400, 400);
      final byteData = await renderedImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;

      final decoded = img.decodeImage(byteData.buffer.asUint8List());
      if (decoded != null) {
        return Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
      }
    } catch (e) {
      AppLogger.d('Code thumbnail skipped: $e', tag: 'ThumbnailGenerator');
    }
    return null;
  }
}
