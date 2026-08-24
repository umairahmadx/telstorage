/// File: thumbnail_generator.dart
/// Description: Component and logic definition for thumbnail_generator.dart in TelStorage.
library;

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:pdfx/pdfx.dart';
import '../utils/app_logger.dart';

import 'thumbnail_helper_native.dart'
    if (dart.library.js_interop) 'thumbnail_helper_web.dart';

Uint8List _isolateProcessImage(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      final resized = img.copyResize(decoded, width: ThumbnailGenerator.maxDimension, height: ThumbnailGenerator.maxDimension);
      final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: ThumbnailGenerator.quality));
      return ThumbnailGenerator.compressUnder5KB(encoded);
    }
  } catch (_) {}
  return bytes;
}

class ThumbnailResult {
  final Uint8List bytes;
  final String extension;
  const ThumbnailResult(this.bytes, this.extension);
}

class ThumbnailGenerator {
  static const int maxDimension = 50;
  static const int quality = 60;
  static const int maxByteSize = 5120; // Strict 5 KB limit

  static Uint8List compressUnder5KB(Uint8List rawBytes) {
    if (rawBytes.length <= maxByteSize) return rawBytes;
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded != null) {
        int q = 50;
        int dim = 45;
        while (dim >= 25) {
          final resized = img.copyResize(decoded, width: dim, height: dim);
          final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: q));
          if (encoded.length <= maxByteSize) return encoded;
          if (q > 20) {
            q -= 15;
          } else {
            dim -= 10;
          }
        }
      }
    } catch (_) {}
    return rawBytes;
  }

  static Future<ThumbnailResult?> generate({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    try {
      Uint8List? thumbBytes;
      String ext = 'jpg';

      if (mimeType.startsWith('image/')) {
        thumbBytes = await generateImageThumbnail(bytes);
        ext = 'jpg';
      } else if (mimeType.startsWith('video/')) {
        thumbBytes = await generateVideoThumbnail(bytes, filename);
        ext = 'jpg';
      } else if (mimeType == 'application/pdf') {
        thumbBytes = await generatePdfThumbnail(bytes);
        ext = 'png';
      }

      if (thumbBytes != null) {
        final compressedBytes = compressUnder5KB(thumbBytes);
        return ThumbnailResult(compressedBytes, ext);
      }
    } catch (e) {
      AppLogger.w('Thumbnail generation failed for $filename ($mimeType): $e',
          tag: 'ThumbnailGenerator');
    }
    return null;
  }

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
    return byteData.buffer.asUint8List();
  }

  static Future<Uint8List> generateVideoThumbnail(
    Uint8List videoBytes,
    String filename,
  ) async {
    final sourcePath =
        await ThumbnailHelper.prepareVideoSource(videoBytes, filename);
    try {
      final uint8list = await VideoThumbnail.thumbnailData(
        video: sourcePath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxDimension,
        quality: quality,
      );
      return uint8list;
    } finally {
      ThumbnailHelper.cleanVideoSource(sourcePath);
    }
  }

  static Future<Uint8List> generatePdfThumbnail(Uint8List pdfBytes) async {
    final document = await PdfDocument.openData(pdfBytes);
    final page = await document.getPage(1);
    final pageImage = await page.render(
      width: page.width * 2,
      height: page.height * 2,
      format: PdfPageImageFormat.png,
    );
    await page.close();
    await document.close();
    if (pageImage == null) throw Exception('Failed to render PDF page');
    return pageImage.bytes;
  }
}
