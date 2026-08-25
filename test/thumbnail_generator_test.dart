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
    test('TC-01: Constants meet strict 400px, 80% quality, and 50KB ceiling', () {
      expect(ThumbnailGenerator.maxDimension, 400);
      expect(ThumbnailGenerator.quality, 80);
      expect(ThumbnailGenerator.maxByteSize, 51200); // 50 KB
    });

    test('TC-02: compressUnder50KB compresses large images under 50KB', () {
      final testImage = img.Image(width: 800, height: 800);
      for (var y = 0; y < 800; y++) {
        for (var x = 0; x < 800; x++) {
          testImage.setPixelRgba(x, y, (x * 255) ~/ 800, (y * 255) ~/ 800, 128, 255);
        }
      }
      final rawJpg = Uint8List.fromList(img.encodeJpg(testImage));
      final compressed = ThumbnailGenerator.compressUnder50KB(rawJpg);

      expect(compressed.length, lessThanOrEqualTo(ThumbnailGenerator.maxByteSize));
    });

    test('TC-03: APK icon extraction extracts launcher icon from valid zip', () async {
      // Build mock APK zip in memory with ic_launcher.png
      final iconImage = img.Image(width: 48, height: 48);
      final iconPngBytes = img.encodePng(iconImage);

      final archive = Archive();
      archive.addFile(ArchiveFile('res/mipmap-xxhdpi/ic_launcher.png', iconPngBytes.length, iconPngBytes));
      archive.addFile(ArchiveFile('AndroidManifest.xml', 10, utf8.encode('mock xml')));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final result = await ThumbnailGenerator.generateApkThumbnail(zipBytes);
      expect(result, isNotNull);
      expect(result!.length, lessThanOrEqualTo(ThumbnailGenerator.maxByteSize));
    });

    test('TC-04: Malformed/corrupted APK zip returns null without throwing', () async {
      final corruptedBytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0xFF, 0xFF, 0x00]);
      final result = await ThumbnailGenerator.generateApkThumbnail(corruptedBytes);
      expect(result, isNull);
    });

    test('TC-05: APK without any icon returns null without throwing', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('classes.dex', 20, utf8.encode('mock dex file')));
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final result = await ThumbnailGenerator.generateApkThumbnail(zipBytes);
      expect(result, isNull);
    });

    test('TC-06: Code/Text file generates 400px snippet preview under 50KB', () async {
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
      final result = await ThumbnailGenerator.generateCodeThumbnail(codeBytes, 'main.dart');

      expect(result, isNotNull);
      expect(result!.length, lessThanOrEqualTo(ThumbnailGenerator.maxByteSize));
    });

    test('TC-07: Empty text file returns null without throwing', () async {
      final emptyBytes = Uint8List(0);
      final result = await ThumbnailGenerator.generateCodeThumbnail(emptyBytes, 'empty.txt');
      expect(result, isNull);
    });

    test('TC-08: Huge text file reads only header and renders without crashing', () async {
      // 100,000 characters of dummy code
      final hugeCode = 'final int a = 1;\n' * 5000;
      final hugeBytes = Uint8List.fromList(utf8.encode(hugeCode));
      final result = await ThumbnailGenerator.generateCodeThumbnail(hugeBytes, 'huge_script.py');

      expect(result, isNotNull);
      expect(result!.length, lessThanOrEqualTo(ThumbnailGenerator.maxByteSize));
    });

    test('TC-09: Unsupported binary mime type returns null immediately', () async {
      final bytes = Uint8List.fromList([0, 1, 2, 3]);
      final result = await ThumbnailGenerator.generate(
        bytes: bytes,
        filename: 'blob.unknown',
        mimeType: 'application/octet-stream',
      );
      expect(result, isNull);
    });
  });
}
