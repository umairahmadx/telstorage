import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:pdfx/pdfx.dart';
import '../utils/app_logger.dart';

import 'thumbnail_helper_native.dart'
    if (dart.library.js_interop) 'thumbnail_helper_web.dart';

class ThumbnailResult {
  final Uint8List bytes;
  final String extension;
  const ThumbnailResult(this.bytes, this.extension);
}

class ThumbnailGenerator {
  static const int maxDimension = 150;
  static const int quality = 70;

  static Future<ThumbnailResult?> generate({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
  }) async {
    try {
      if (mimeType.startsWith('image/')) {
        final thumbBytes = await generateImageThumbnail(bytes);
        return ThumbnailResult(thumbBytes, 'jpg');
      } else if (mimeType.startsWith('video/')) {
        final thumbBytes = await generateVideoThumbnail(bytes, filename);
        return ThumbnailResult(thumbBytes, 'jpg');
      } else if (mimeType == 'application/pdf') {
        final thumbBytes = await generatePdfThumbnail(bytes);
        return ThumbnailResult(thumbBytes, 'png');
      }
    } catch (e) {
      AppLogger.w('Thumbnail generation failed for $filename ($mimeType): $e',
          tag: 'ThumbnailGenerator');
    }
    return null;
  }

  static Future<Uint8List> generateImageThumbnail(Uint8List bytes) async {
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
