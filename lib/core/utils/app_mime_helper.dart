/*
 * File: app_mime_helper.dart
 * Description: Centralized MIME detection and media classification helper with complete support for standard, raw, vector, and specialized media types.
 */

import 'package:mime/mime.dart';

/// Utility class providing robust MIME type detection and classification.
class AppMimeHelper {
  AppMimeHelper._();

  /// Known extension mappings for image, raw camera, and vector types not always present in standard MIME tables.
  static const Map<String, String> _customImageMimeMap = {
    'jfif': 'image/jpeg',
    'pjpeg': 'image/jpeg',
    'pjp': 'image/jpeg',
    'apng': 'image/png',
    'cur': 'image/x-icon',
    'ico': 'image/x-icon',
    'dib': 'image/bmp',
    'rle': 'image/bmp',
    'bmp': 'image/bmp',
    'tif': 'image/tiff',
    'tiff': 'image/tiff',
    'avif': 'image/avif',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'svg': 'image/svg+xml',
    'jxl': 'image/jxl',
    'jp2': 'image/jp2',
    'j2k': 'image/jp2',
    'j2c': 'image/x-jp2-codestream',
    'jpx': 'image/jpx',
    'cr2': 'image/x-canon-cr2',
    'cr3': 'image/x-canon-cr3',
    'nef': 'image/x-nikon-nef',
    'arw': 'image/x-sony-arw',
    'dng': 'image/x-adobe-dng',
    'bay': 'image/x-casio-bay',
    'raw': 'image/x-raw',
    'eps': 'application/postscript',
  };

  /// Set of all 33 image, RAW, vector, and advanced image extensions (without leading dot).
  static const Set<String> allImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'bmp',
    'heic',
    'heif',
    'ico',
    'cur',
    'tif',
    'tiff',
    'svg',
    'jfif',
    'pjpeg',
    'pjp',
    'apng',
    'dib',
    'rle',
    'avif',
    'jxl',
    'jp2',
    'j2k',
    'j2c',
    'jpx',
    'arw',
    'cr2',
    'cr3',
    'nef',
    'dng',
    'bay',
    'raw',
    'eps',
  };

  /// Set of camera RAW file extensions.
  static const Set<String> cameraRawExtensions = {
    'arw',
    'cr2',
    'cr3',
    'nef',
    'dng',
    'bay',
    'raw',
  };

  /// Set of JPEG 2000 extensions.
  static const Set<String> jpeg2000Extensions = {
    'jp2',
    'j2k',
    'j2c',
    'jpx',
  };

  /// Resolves the MIME type for a given filename with fallbacks for specialized formats.
  static String detectMimeType(String filename) {
    final lower = filename.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    if (_customImageMimeMap.containsKey(ext)) {
      return _customImageMimeMap[ext]!;
    }

    return lookupMimeType(filename) ?? 'application/octet-stream';
  }

  /// Checks whether a given filename represents an image format.
  static bool isImageExtension(String filename) {
    final lower = filename.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';
    return allImageExtensions.contains(ext);
  }
}
