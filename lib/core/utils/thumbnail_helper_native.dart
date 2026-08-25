/*
 * File: thumbnail_helper_native.dart
 * Description: Platform file helper caching 400px WebP media thumbnails to device disk.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

class ThumbnailHelper {
  static Future<String> prepareVideoSource(Uint8List bytes, String name) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/temp_thumb_$name');
    await tempFile.writeAsBytes(bytes);
    return tempFile.path;
  }

  static void cleanVideoSource(String source) {
    try {
      final file = File(source);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  static Future<String?> cachedThumbnailPath(String fileId) async {
    final tempDir = await getTemporaryDirectory();
    final webpFile = File('${tempDir.path}/thumbnails/$fileId.webp');
    if (webpFile.existsSync()) return webpFile.path;
    final jpgFile = File('${tempDir.path}/thumbnails/$fileId.jpg');
    return jpgFile.existsSync() ? jpgFile.path : null;
  }

  static Future<String> cacheThumbnail(String fileId, Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final directory = Directory('${tempDir.path}/thumbnails');
    await directory.create(recursive: true);
    final file = File('${directory.path}/$fileId.webp');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<String?> cachedVideoThumbnailPath(String fileId) async {
    final tempDir = await getTemporaryDirectory();
    final webpFile = File('${tempDir.path}/video_thumbs/$fileId.webp');
    if (webpFile.existsSync()) return webpFile.path;
    final jpgFile = File('${tempDir.path}/video_thumbs/$fileId.jpg');
    return jpgFile.existsSync() ? jpgFile.path : null;
  }

  static Future<String?> generateVideoThumbnail(
      String fileId, String videoPath) async {
    final tempDir = await getTemporaryDirectory();
    final directory = Directory('${tempDir.path}/video_thumbs');
    await directory.create(recursive: true);
    final thumbnail = await VideoThumbnail.thumbnailFile(
      video: videoPath,
      thumbnailPath: directory.path,
      imageFormat: ImageFormat.WEBP,
      maxWidth: 400,
      quality: 80,
    );
    return thumbnail.path;
  }

  static ImageProvider? imageProviderFromPath(String path) =>
      FileImage(File(path));
}
