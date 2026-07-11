import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';

import 'thumbnail_helper_native.dart'
    if (dart.library.js_interop) 'thumbnail_helper_web.dart';

class ThumbnailGenerator {
  static const int maxDimension = 150;
  static const int quality = 70;

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
    final sourcePath = await ThumbnailHelper.prepareVideoSource(videoBytes, filename);
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
}
