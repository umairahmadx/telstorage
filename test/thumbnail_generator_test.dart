/*
 * File: thumbnail_generator_test.dart
 * Description: Comprehensive unit tests validating 400px WebP thumbnails, APK icon extraction, code snippet generation, and <=50KB compression.
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:telstorage/core/utils/thumbnail_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThumbnailGenerator Configuration & Size Tests', () {
    test('TC-01: Constants meet strict 400px, 80% quality, and 50KB ceiling',
        () {
      expect(ThumbnailGenerator.maxDimension, 400);
      expect(ThumbnailGenerator.quality, 80);
      expect(ThumbnailGenerator.maxByteSize, 51200); // 50 KB
    });

    test('TC-02: compressUnder50KB compresses large images under 50KB', () {
      final testImage = img.Image(width: 800, height: 800);
      for (var y = 0; y < 800; y++) {
        for (var x = 0; x < 800; x++) {
          testImage.setPixelRgba(
              x, y, (x * 255) ~/ 800, (y * 255) ~/ 800, 128, 255);
        }
      }
      final rawJpg = Uint8List.fromList(img.encodeJpg(testImage));
      final compressed = ThumbnailGenerator.compressUnder50KB(rawJpg);

      expect(compressed, isNotNull);
      expect(compressed!.length,
          lessThanOrEqualTo(ThumbnailGenerator.maxByteSize));
    });

    test('TC-03: APK icon extraction extracts launcher icon from valid zip',
        () async {
      // Build mock APK zip in memory with ic_launcher.png
      final iconImage = img.Image(width: 48, height: 48);
      final iconPngBytes = img.encodePng(iconImage);

      final archive = Archive();
      archive.addFile(ArchiveFile('res/mipmap-xxhdpi/ic_launcher.png',
          iconPngBytes.length, iconPngBytes));
      archive.addFile(
          ArchiveFile('AndroidManifest.xml', 10, utf8.encode('mock xml')));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final result = await ThumbnailGenerator.generateApkThumbnail(zipBytes);
      expect(result, isNotNull);
      expect(result!.length, lessThanOrEqualTo(ThumbnailGenerator.maxByteSize));
    });

    test('TC-04: Malformed/corrupted APK zip returns null without throwing',
        () async {
      final corruptedBytes =
          Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0xFF, 0xFF, 0x00]);
      final result =
          await ThumbnailGenerator.generateApkThumbnail(corruptedBytes);
      expect(result, isNull);
    });

    test('TC-05: APK without any icon returns null without throwing', () async {
      final archive = Archive();
      archive.addFile(
          ArchiveFile('classes.dex', 20, utf8.encode('mock dex file')));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final result = await ThumbnailGenerator.generateApkThumbnail(zipBytes);
      expect(result, isNull);
    });

    test('TC-06: Code/Text file generates 400px snippet preview under 50KB',
        () async {
      const sampleCode = '''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: Scaffold());
  }
}
''';
      final codeBytes = Uint8List.fromList(utf8.encode(sampleCode));
      final result = await ThumbnailGenerator.generateCodeThumbnail(
          codeBytes, 'main.dart');

      expect(result, isNotNull);
      expect(result!.length, lessThanOrEqualTo(ThumbnailGenerator.maxByteSize));
    });

    test('TC-07: Empty text file returns null without throwing', () async {
      final emptyBytes = Uint8List(0);
      final result = await ThumbnailGenerator.generateCodeThumbnail(
          emptyBytes, 'empty.txt');
      expect(result, isNull);
    });

    test('TC-08: Huge text file reads only header and renders without crashing',
        () async {
      // 100,000 characters of dummy code
      final hugeCode = 'final int a = 1;\n' * 5000;
      final hugeBytes = Uint8List.fromList(utf8.encode(hugeCode));
      final result = await ThumbnailGenerator.generateCodeThumbnail(
          hugeBytes, 'huge_script.py');

      expect(result, isNotNull);
      expect(result!.length, lessThanOrEqualTo(ThumbnailGenerator.maxByteSize));
    });

    test('TC-09: Unsupported binary mime type returns null immediately',
        () async {
      final bytes = Uint8List.fromList([0, 1, 2, 3]);
      final result = await ThumbnailGenerator.generate(
        bytes: bytes,
        filename: 'blob.unknown',
        mimeType: 'application/octet-stream',
      );
      expect(result, isNull);
    });

    test(
        'TC-10: Undecodable raw binary image returns null and never leaks oversized payload',
        () async {
      // 100KB of random undecodable bytes
      final rawFakeBytes = Uint8List(100 * 1024);
      final result = await ThumbnailGenerator.generate(
        bytes: rawFakeBytes,
        filename: 'corrupted_photo.heic',
        mimeType: 'image/heic',
      );
      expect(result, isNull);
    });

    test('TC-11: compressUnder50KB returns null on undecodable oversized data',
        () {
      final largeGarbage = Uint8List(200 * 1024);
      final result = ThumbnailGenerator.compressUnder50KB(largeGarbage);
      expect(result, isNull);
    });

    test(
        'TC-12: Non-1:1 aspect ratio banner maintains aspect ratio when generated',
        () async {
      // 16:4 aspect ratio image (800 x 200)
      final bannerImage = img.Image(width: 800, height: 200);
      final bannerBytes = Uint8List.fromList(img.encodeJpg(bannerImage));
      final result = await ThumbnailGenerator.generate(
        bytes: bannerBytes,
        filename: 'banner.jpg',
        mimeType: 'image/jpeg',
      );
      expect(result, isNotNull);
      expect(result!.extension, 'jpg');

      final decoded = img.decodeImage(result.bytes);
      expect(decoded, isNotNull);
      // Width should be 400 and height should be 100 (exact 4:1 / 16:4 ratio maintained, not square 400x400)
      expect(decoded!.width, 400);
      expect(decoded.height, 100);
    });

    test(
        'TC-13: ThumbnailGenerator.generate returns extension jpg for all supported types',
        () async {
      final testImage = img.Image(width: 400, height: 300);
      final imageBytes = Uint8List.fromList(img.encodeJpg(testImage));

      final result = await ThumbnailGenerator.generate(
        bytes: imageBytes,
        filename: 'landscape.jpg',
        mimeType: 'image/jpeg',
      );

      expect(result, isNotNull);
      expect(result!.extension, 'jpg');
      expect(result.bytes.length,
          lessThanOrEqualTo(ThumbnailGenerator.maxByteSize));
    });

    test('TC-14: ThumbnailGenerator extracts embedded JPEG from HEIC file',
        () async {
      final innerImage = img.Image(width: 200, height: 200);
      final jpegBytes = img.encodeJpg(innerImage);

      // Construct a mock HEIC container with dummy ftyp box prefix followed by valid JPEG bytes
      final mockHeicBytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69,
        0x63, // ftypheic box
        0x00, 0x00, 0x00, 0x00,
        ...jpegBytes,
        0x00, 0x00, 0x00, 0x08, 0x6D, 0x65, 0x74, 0x61, // meta box trailing
      ]);

      final result = await ThumbnailGenerator.generate(
        bytes: mockHeicBytes,
        filename: 'photo.heic',
        mimeType: 'image/heic',
      );

      expect(result, isNotNull);
      expect(result!.extension, 'jpg');
      expect(result.bytes.length,
          lessThanOrEqualTo(ThumbnailGenerator.maxByteSize));
    });
  });
}
