/*
 * File: thumbnail_helper_web.dart
 * Description: Component and logic definition for thumbnail_helper_web.dart in TelStorage.
 */

import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart';

class ThumbnailHelper {
  static Future<String> prepareVideoSource(Uint8List bytes, String name) async {
    final blob = Blob([bytes.toJS].toJS);
    return URL.createObjectURL(blob);
  }

  static void cleanVideoSource(String source) {
    try {
      URL.revokeObjectURL(source);
    } catch (_) {}
  }

  static Future<String?> cachedThumbnailPath(String fileId) async => null;

  static Future<String> cacheThumbnail(String fileId, Uint8List bytes) =>
      throw UnsupportedError('Thumbnail file caching is not available on web');

  static Future<String?> cachedVideoThumbnailPath(String fileId) async => null;

  static Future<String?> generateVideoThumbnail(
          String fileId, String videoPath) async =>
      null;

  static Future<void> deleteCachedThumbnail(String fileId) async {}

  static ImageProvider? imageProviderFromPath(String path) => null;
}
