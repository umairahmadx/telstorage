/*
 * File: media_formats_support_test.dart
 * Description: Tests coverage for 33 image, RAW camera, vector, and advanced formats across MIME detection, browser filtering, image viewer cache, and thumbnail generation.
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:j2k/j2k.dart' as j2k;
import 'package:koni_jxl/koni_jxl.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/image_viewer_cache_service.dart';
import 'package:telstorage/core/utils/app_mime_helper.dart';
import 'package:telstorage/core/utils/thumbnail_generator.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_filter_helper.dart';

void main() {
  const all33Extensions = [
    '.apng', '.arw', '.avif', '.bay', '.bmp', '.cr2', '.cr3', '.cur', '.dib',
    '.dng', '.eps', '.gif', '.heic', '.heif', '.ico', '.j2c', '.j2k', '.jpeg',
    '.jfif', '.jpg', '.jp2', '.jpx', '.jxl', '.nef', '.pjp', '.pjpeg', '.png',
    '.raw', '.rle', '.svg', '.tif', '.tiff', '.webp'
  ];

  group('Media Formats Recognition (All 33 Extensions)', () {
    test('All 33 extensions are identified as viewable images', () {
      for (final ext in all33Extensions) {
        final filename = 'photo$ext';
        final mime = AppMimeHelper.detectMimeType(filename);
        final file = FileRecord(
          fileId: 'test_$ext',
          name: filename,
          metadataMessageId: 1,
          sizeMb: 1.0,
          mimeType: mime,
          uploadedAt: DateTime.now(),
          chunkCount: 1,
          sha256Hash: 'hash_$ext',
        );

        expect(
          ImageViewerCacheService.isImageRecord(file),
          isTrue,
          reason: 'Extension $ext should be recognized as viewable in ImageViewerCacheService',
        );

        expect(
          BrowserFilterHelper.matchesCategory(file, 'image'),
          isTrue,
          reason: 'Extension $ext should match "image" category in BrowserFilterHelper',
        );
      }
    });

    test('AppMimeHelper assigns proper image MIME types to all 33 extensions', () {
      for (final ext in all33Extensions) {
        final filename = 'photo$ext';
        final mime = AppMimeHelper.detectMimeType(filename);
        expect(
          mime.startsWith('image/') || mime == 'application/postscript',
          isTrue,
          reason: 'Extension $ext should have valid image or postscript mime, got $mime',
        );
      }
    });
  });

  group('Thumbnail Generation for Advanced Formats', () {
    test('Generates thumbnail for standard image (JPEG/PNG/BMP)', () async {
      final testImg = img.Image(width: 200, height: 100);
      img.fill(testImg, color: img.ColorRgb8(255, 0, 0));
      final pngBytes = Uint8List.fromList(img.encodePng(testImg));

      final thumb = await ThumbnailGenerator.generate(
        bytes: pngBytes,
        filename: 'test.png',
        mimeType: 'image/png',
      );

      expect(thumb, isNotNull);
      expect(thumb!.bytes.length, lessThanOrEqualTo(50 * 1024));
    });

    test('Generates thumbnail for JFIF / PJPEG / PJP', () async {
      final testImg = img.Image(width: 150, height: 150);
      img.fill(testImg, color: img.ColorRgb8(0, 255, 0));
      final jpgBytes = Uint8List.fromList(img.encodeJpg(testImg));

      final thumb = await ThumbnailGenerator.generate(
        bytes: jpgBytes,
        filename: 'sample.jfif',
        mimeType: 'image/jpeg',
      );

      expect(thumb, isNotNull);
      expect(thumb!.bytes.length, lessThanOrEqualTo(50 * 1024));
    });

    test('Generates thumbnail for SVG vector', () async {
      const svgStr = '''
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
  <rect width="100" height="100" fill="#0066cc" />
  <circle cx="50" cy="50" r="40" fill="#ffffff" />
</svg>
''';
      final svgBytes = Uint8List.fromList(utf8.encode(svgStr));

      final thumb = await ThumbnailGenerator.generate(
        bytes: svgBytes,
        filename: 'graphic.svg',
        mimeType: 'image/svg+xml',
      );

      expect(thumb, isNotNull);
      expect(thumb!.bytes.length, lessThanOrEqualTo(50 * 1024));
    });

    test('Extracts embedded JPEG preview from simulated Camera RAW file', () async {
      // Create a valid preview JPEG
      final previewImg = img.Image(width: 120, height: 90);
      img.fill(previewImg, color: img.ColorRgb8(0, 0, 255));
      final previewJpg = Uint8List.fromList(img.encodeJpg(previewImg));

      // Simulate a RAW container (.cr2 / .dng / .nef / .arw) with arbitrary header prefix and trailing data
      final rawBytes = Uint8List(previewJpg.length + 512);
      // Dummy TIFF/RAW header
      rawBytes[0] = 0x49; // 'I'
      rawBytes[1] = 0x49; // 'I'
      rawBytes[2] = 0x2A; // 42
      rawBytes[3] = 0x00;
      // Inject preview JPEG at offset 128
      rawBytes.setRange(128, 128 + previewJpg.length, previewJpg);

      final thumb = await ThumbnailGenerator.generate(
        bytes: rawBytes,
        filename: 'capture.cr2',
        mimeType: 'image/x-canon-cr2',
      );

      expect(thumb, isNotNull);
      expect(thumb!.bytes.length, lessThanOrEqualTo(50 * 1024));
    });

    test('Extracts embedded TIFF preview from DOS EPS binary file', () async {
      // Create a valid TIFF preview image
      final previewImg = img.Image(width: 80, height: 80);
      img.fill(previewImg, color: img.ColorRgb8(255, 128, 0));
      final tiffBytes = Uint8List.fromList(img.encodeTiff(previewImg));

      // Build 30-byte DOS EPS header:
      // Byte 0-3: 0xC5, 0xD0, 0xD3, 0xC6
      // Byte 4-7: PS offset = 30
      // Byte 8-11: PS length = 20
      // Byte 12-15: WMF offset = 0
      // Byte 16-19: WMF length = 0
      // Byte 20-23: TIFF offset = 50
      // Byte 24-27: TIFF length = tiffBytes.length
      // Byte 28-29: Checksum = 0xFFFF
      final epsData = Uint8List(50 + tiffBytes.length);
      final bdata = ByteData.sublistView(epsData);
      bdata.setUint8(0, 0xC5);
      bdata.setUint8(1, 0xD0);
      bdata.setUint8(2, 0xD3);
      bdata.setUint8(3, 0xC6);
      bdata.setUint32(4, 30, Endian.little); // PS offset
      bdata.setUint32(8, 20, Endian.little); // PS len
      bdata.setUint32(12, 0, Endian.little); // WMF offset
      bdata.setUint32(16, 0, Endian.little); // WMF len
      bdata.setUint32(20, 50, Endian.little); // TIFF offset
      bdata.setUint32(24, tiffBytes.length, Endian.little); // TIFF len
      bdata.setUint16(28, 0xFFFF, Endian.little);

      // Copy TIFF bytes at offset 50
      epsData.setRange(50, 50 + tiffBytes.length, tiffBytes);

      final thumb = await ThumbnailGenerator.generate(
        bytes: epsData,
        filename: 'logo.eps',
        mimeType: 'application/postscript',
      );

      expect(thumb, isNotNull);
      expect(thumb!.bytes.length, lessThanOrEqualTo(50 * 1024));
    });

    test('Generates thumbnail for JPEG XL (.jxl)', () async {
      final rgba = Uint8List(100 * 100 * 4);
      for (int i = 0; i < rgba.length; i += 4) {
        rgba[i] = 200;
        rgba[i + 1] = 80;
        rgba[i + 2] = 40;
        rgba[i + 3] = 255;
      }
      final jxlBytes = JxlEncoder.encodeLossless(
        rgba,
        width: 100,
        height: 100,
        hasAlpha: true,
      );

      final thumb = await ThumbnailGenerator.generate(
        bytes: jxlBytes,
        filename: 'artwork.jxl',
        mimeType: 'image/jxl',
      );

      expect(thumb, isNotNull);
      expect(thumb!.bytes.length, lessThanOrEqualTo(50 * 1024));
    });

    test('Generates thumbnail for JPEG 2000 (.jp2 / .j2k)', () async {
      final rgba = Uint8List(100 * 100 * 4);
      for (int i = 0; i < rgba.length; i += 4) {
        rgba[i] = 50;
        rgba[i + 1] = 120;
        rgba[i + 2] = 220;
        rgba[i + 3] = 255;
      }
      final jp2Bytes = j2k.encodeJpeg2000Pixels(
        rgba,
        width: 100,
        height: 100,
        components: 4,
        options: const j2k.Jpeg2000EncodeOptions(wrapInJp2: true),
      );

      final thumb = await ThumbnailGenerator.generate(
        bytes: jp2Bytes,
        filename: 'satellite.jp2',
        mimeType: 'image/jp2',
      );

      expect(thumb, isNotNull);
      expect(thumb!.bytes.length, lessThanOrEqualTo(50 * 1024));
    });
  });
}
