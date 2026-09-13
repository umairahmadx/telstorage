/*
 * File: media_preview_helper.dart
 * Description: Universal codec and preview extraction helper supporting Camera RAW, DOS EPS, JPEG 2000, JPEG XL, and standard images.
 */

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:j2k/j2k.dart' as j2k;
import 'package:koni_jxl/koni_jxl.dart';
import 'app_logger.dart';

/// Helper methods for decoding and extracting viewable bitmap previews from specialized media formats.
class MediaPreviewHelper {
  MediaPreviewHelper._();

  /// Scans container bytes to extract an embedded JPEG preview stream.
  ///
  /// Camera RAW files (CR2, CR3, NEF, ARW, DNG, BAY, RAW) and HEIC/HEIF
  /// files contain high-resolution embedded JPEG streams starting with SOI (0xFF, 0xD8, 0xFF)
  /// and ending with EOI (0xFF, 0xD9).
  static Uint8List? extractEmbeddedJpeg(Uint8List bytes) {
    try {
      final int length = bytes.length;
      if (length < 100) return null;

      Uint8List? bestCandidate;
      int bestCandidateSize = 0;

      // Scan for JPEG SOI marker (0xFF, 0xD8, 0xFF)
      final int searchLimit = length > 20000000 ? 20000000 : length - 4;
      for (int i = 0; i < searchLimit; i++) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8 && bytes[i + 2] == 0xFF) {
          // Scan ahead for matching EOI marker (0xFF, 0xD9)
          final maxScan = (i + 10000000).clamp(0, length - 1);
          for (int j = i + 64; j < maxScan; j++) {
            if (bytes[j] == 0xFF && bytes[j + 1] == 0xD9) {
              final candidate = bytes.sublist(i, j + 2);
              if (candidate.length > bestCandidateSize) {
                // Verify candidate is a decodable JPEG image
                final headerInfo = img.decodeJpg(candidate);
                if (headerInfo != null &&
                    headerInfo.width >= 30 &&
                    headerInfo.height >= 30) {
                  bestCandidate = candidate;
                  bestCandidateSize = candidate.length;
                }
              }
              // Skip past this JPEG stream
              i = j + 1;
              break;
            }
          }
        }
      }

      return bestCandidate;
    } catch (e) {
      AppLogger.d('Embedded JPEG extraction failed: $e',
          tag: 'MediaPreviewHelper');
      return null;
    }
  }

  /// Extracts embedded TIFF preview from a DOS EPS binary file header (0xC5, 0xD0, 0xD3, 0xC6).
  static Uint8List? extractDosEpsTiff(Uint8List bytes) {
    try {
      if (bytes.length < 30) return null;
      if (bytes[0] == 0xC5 &&
          bytes[1] == 0xD0 &&
          bytes[2] == 0xD3 &&
          bytes[3] == 0xC6) {
        final bdata = ByteData.sublistView(bytes);
        final tiffOffset = bdata.getUint32(20, Endian.little);
        final tiffLength = bdata.getUint32(24, Endian.little);

        if (tiffLength > 0 && (tiffOffset + tiffLength) <= bytes.length) {
          return bytes.sublist(tiffOffset, tiffOffset + tiffLength);
        }
      }
    } catch (e) {
      AppLogger.d('DOS EPS TIFF extraction failed: $e',
          tag: 'MediaPreviewHelper');
    }
    return null;
  }

  /// Decodes JPEG 2000 (JP2 / J2K / JPX) stream into an [img.Image] using pure Dart `package:j2k`.
  static img.Image? decodeJpeg2000(Uint8List bytes) {
    try {
      final decoded = j2k.decodeJpeg2000(
        bytes,
        options: const j2k.Jpeg2000DecodeOptions(maxPixels: 32 * 1024 * 1024),
      );

      return img.Image.fromBytes(
        width: decoded.width,
        height: decoded.height,
        bytes: decoded.pixels.buffer,
        numChannels: decoded.hasAlpha ? 4 : 3,
      );
    } catch (e) {
      AppLogger.d('JPEG 2000 decode failed: $e', tag: 'MediaPreviewHelper');
      return null;
    }
  }

  /// Decodes JPEG XL (JXL) stream into an [img.Image] using pure Dart `package:koni_jxl`.
  static img.Image? decodeJpegXl(Uint8List bytes) {
    try {
      final jxlImage = JxlDecoder.decode(bytes);
      final rgba = jxlImage.toRgba8();

      return img.Image.fromBytes(
        width: jxlImage.width,
        height: jxlImage.height,
        bytes: rgba.buffer,
        numChannels: 4,
      );
    } catch (e) {
      AppLogger.d('JPEG XL decode failed: $e', tag: 'MediaPreviewHelper');
      return null;
    }
  }

  /// Decodes or extracts viewable JPEG/PNG payload for caching and rendering in the viewer.
  static Future<Uint8List> prepareViewableBytes({
    required Uint8List rawBytes,
    required String filename,
  }) async {
    final lower = filename.toLowerCase();
    final ext = lower.contains('.') ? lower.split('.').last : '';

    // 1. Camera RAW: Extract embedded high-res JPEG preview
    if ({'cr2', 'cr3', 'nef', 'arw', 'dng', 'bay', 'raw'}.contains(ext)) {
      final embedded = await compute(extractEmbeddedJpeg, rawBytes);
      if (embedded != null) {
        return embedded;
      }
    }

    // 2. DOS EPS: Extract embedded TIFF preview
    if (ext == 'eps') {
      final tiffBytes = extractDosEpsTiff(rawBytes);
      if (tiffBytes != null) {
        final decodedTiff = img.decodeTiff(tiffBytes);
        if (decodedTiff != null) {
          return Uint8List.fromList(img.encodeJpg(decodedTiff, quality: 90));
        }
      }
    }

    // 3. JPEG 2000: Decode in isolate to standard JPEG
    if ({'jp2', 'j2k', 'j2c', 'jpx'}.contains(ext)) {
      final decoded = await compute(decodeJpeg2000, rawBytes);
      if (decoded != null) {
        return Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
      }
    }

    // 4. JPEG XL: Decode in isolate to standard JPEG
    if (ext == 'jxl') {
      final decoded = await compute(decodeJpegXl, rawBytes);
      if (decoded != null) {
        return Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
      }
    }

    // Return original bytes for standard images and SVG vectors
    return rawBytes;
  }
}
