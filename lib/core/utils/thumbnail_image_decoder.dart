/*
 * File: thumbnail_image_decoder.dart
 * Description: Modular image thumbnail decoder supporting all 33 raster, RAW camera, vector, and advanced image formats.
 */

import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;
import 'app_logger.dart';
import 'app_mime_helper.dart';
import 'media_preview_helper.dart';
import 'thumbnail_generator.dart';

/// Helper class specializing in image thumbnail decoding across all media formats.
class ThumbnailImageDecoder {
  ThumbnailImageDecoder._();

  /// Maximum target dimension for thumbnails.
  static const int maxDimension = 400;

  /// Compression quality for thumbnail output.
  static const int quality = 80;

  /// Decodes and generates a <= 50KB JPEG thumbnail from arbitrary image bytes and filename.
  static Future<Uint8List?> decodeThumbnail({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    final lower = filename.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    // 1. Vector SVG rendering
    if (ext == 'svg' || mimeType == 'image/svg+xml') {
      final svgThumb = await _renderSvgThumbnail(bytes);
      if (svgThumb != null) return svgThumb;
    }

    // 2. Camera RAW: Embedded JPEG extraction
    if (AppMimeHelper.cameraRawExtensions.contains(ext)) {
      final embedded = await compute(MediaPreviewHelper.extractEmbeddedJpeg, bytes);
      if (embedded != null) {
        final thumb = await _downsampleAndCompress(embedded);
        if (thumb != null) return thumb;
      }
    }

    // 3. DOS EPS Binary Header: Embedded TIFF extraction
    if (ext == 'eps') {
      final tiffBytes = MediaPreviewHelper.extractDosEpsTiff(bytes);
      if (tiffBytes != null) {
        final decodedTiff = img.decodeTiff(tiffBytes);
        if (decodedTiff != null) {
          final encoded = _resizeAndEncode(decodedTiff);
          if (encoded != null) return encoded;
        }
      }
    }

    // 4. JPEG 2000 (JP2 / J2K / JPX)
    if (AppMimeHelper.jpeg2000Extensions.contains(ext) ||
        mimeType.contains('jp2') ||
        mimeType.contains('jpeg2000')) {
      final decodedJ2k = await compute(MediaPreviewHelper.decodeJpeg2000, bytes);
      if (decodedJ2k != null) {
        final encoded = _resizeAndEncode(decodedJ2k);
        if (encoded != null) return encoded;
      }
    }

    // 5. JPEG XL (JXL)
    if (ext == 'jxl' || mimeType == 'image/jxl') {
      final decodedJxl = await compute(MediaPreviewHelper.decodeJpegXl, bytes);
      if (decodedJxl != null) {
        final encoded = _resizeAndEncode(decodedJxl);
        if (encoded != null) return encoded;
      }
    }

    // 6. Hardware-accelerated Skia downsampling (JPG, PNG, WebP, GIF, BMP, ICO, AVIF)
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: maxDimension,
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? byteData = await fi.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        final decoded = img.decodeImage(byteData.buffer.asUint8List());
        if (decoded != null) {
          final encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
          return ThumbnailGenerator.compressUnder50KB(encoded);
        }
      }
    } catch (e) {
      AppLogger.d('Native image codec decode failed/skipped: $e',
          tag: 'ThumbnailImageDecoder');
    }

    // 7. General fallback decode via background isolate (TIFF, BMP variants, etc.)
    try {
      final isolateResult = await compute(_isolateProcessImage, bytes);
      if (isolateResult != null &&
          isolateResult.length <= ThumbnailGenerator.maxByteSize) {
        return isolateResult;
      }
    } catch (_) {}

    return null;
  }

  /// Renders scalable vector graphics to a 400px JPEG thumbnail.
  static Future<Uint8List?> _renderSvgThumbnail(Uint8List bytes) async {
    try {
      final rawSvg = utf8.decode(bytes, allowMalformed: true);
      final PictureInfo pictureInfo =
          await vg.loadPicture(SvgStringLoader(rawSvg), null);

      final size = pictureInfo.size;
      int targetW = size.width.round();
      int targetH = size.height.round();

      if (targetW <= 0 || targetH <= 0) {
        targetW = maxDimension;
        targetH = maxDimension;
      } else if (targetW > maxDimension || targetH > maxDimension) {
        if (targetW >= targetH) {
          targetH = (targetH * maxDimension / targetW).round();
          targetW = maxDimension;
        } else {
          targetW = (targetW * maxDimension / targetH).round();
          targetH = maxDimension;
        }
      }

      final ui.Image rendered = await pictureInfo.picture.toImage(
        targetW.clamp(1, maxDimension),
        targetH.clamp(1, maxDimension),
      );
      pictureInfo.picture.dispose();

      final ByteData? byteData =
          await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (byteData != null) {
        final decoded = img.decodeImage(byteData.buffer.asUint8List());
        if (decoded != null) {
          final encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
          return ThumbnailGenerator.compressUnder50KB(encoded);
        }
      }
    } catch (e) {
      AppLogger.d('SVG thumbnail rendering failed: $e', tag: 'ThumbnailImageDecoder');
    }
    return null;
  }

  /// Downsamples an image buffer to 400px and compresses to <= 50KB.
  static Future<Uint8List?> _downsampleAndCompress(Uint8List candidate) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        candidate,
        targetWidth: maxDimension,
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? byteData = await fi.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        final decoded = img.decodeImage(byteData.buffer.asUint8List());
        if (decoded != null) {
          final encoded = Uint8List.fromList(img.encodeJpg(decoded, quality: quality));
          return ThumbnailGenerator.compressUnder50KB(encoded);
        }
      }
    } catch (_) {
      final isolateResult = await compute(_isolateProcessImage, candidate);
      if (isolateResult != null) return isolateResult;
    }
    return null;
  }

  /// Resizes [img.Image] and encodes to compressed JPEG.
  static Uint8List? _resizeAndEncode(img.Image decoded) {
    int targetW = decoded.width;
    int targetH = decoded.height;
    if (targetW > maxDimension || targetH > maxDimension) {
      if (targetW >= targetH) {
        targetH = (targetH * maxDimension / targetW).round();
        targetW = maxDimension;
      } else {
        targetW = (targetW * maxDimension / targetH).round();
        targetH = maxDimension;
      }
    }
    final resized = img.copyResize(decoded, width: targetW, height: targetH);
    final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    return ThumbnailGenerator.compressUnder50KB(encoded);
  }

  /// Background isolate processing for standard image resizing.
  static Uint8List? _isolateProcessImage(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        return _resizeAndEncode(decoded);
      }
    } catch (_) {}
    return null;
  }
}
