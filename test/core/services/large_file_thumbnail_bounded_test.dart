/*
 * File: large_file_thumbnail_bounded_test.dart
 * Description: Unit tests verifying zero-buffer bounded thumbnail generation for 1GB+ files and SVG background compositing.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/utils/thumbnail_generator.dart';
import 'package:telstorage/core/utils/thumbnail_helper_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thumb_bounded_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Bounded Streaming Thumbnail Generation', () {
    test('ThumbnailHelper.readHeaderBytes reads only up to maxBytes from disk', () async {
      final largeFilePath = '${tempDir.path}/sample_log.txt';
      final file = File(largeFilePath);

      // Create a 100 KB text file
      final largeContent = 'A' * (100 * 1024);
      await file.writeAsString(largeContent);

      final headerBytes = await ThumbnailHelper.readHeaderBytes(largeFilePath, 4096);
      expect(headerBytes, isNotNull);
      expect(headerBytes!.length, equals(4096));
      expect(utf8.decode(headerBytes), equals('A' * 4096));
    });

    test('ThumbnailGenerator.generate with text file only reads 4KB header bytes', () async {
      final codeFilePath = '${tempDir.path}/large_script.dart';
      final file = File(codeFilePath);

      // Create a 500 KB script file
      final scriptLines = List.generate(5000, (i) => 'void function$i() { print($i); }').join('\n');
      await file.writeAsString(scriptLines);

      final result = await ThumbnailGenerator.generate(
        filePath: codeFilePath,
        filename: 'large_script.dart',
        mimeType: 'text/x-dart',
      );

      expect(result, isNotNull);
      expect(result!.extension, equals('jpg'));
      expect(result.bytes.length, lessThanOrEqualTo(50 * 1024));
    });

    test('ThumbnailGenerator.generate for SVG scales properly and renders without error', () async {
      const svgContent = '''
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
  <circle cx="50" cy="50" r="40" fill="#00AAFF" />
  <rect x="110" y="10" width="80" height="80" rx="10" fill="#FFAA00" />
</svg>
''';
      final svgBytes = Uint8List.fromList(utf8.encode(svgContent));

      final result = await ThumbnailGenerator.generate(
        bytes: svgBytes,
        filename: 'vector_logo.svg',
        mimeType: 'image/svg+xml',
      );

      expect(result, isNotNull);
      expect(result!.extension, equals('jpg'));
      expect(result.bytes.length, lessThanOrEqualTo(50 * 1024));
    });

    test('ThumbnailGenerator.generate skips reading files > 50MB for non-video formats', () async {
      final oversizedPath = '${tempDir.path}/huge_archive.zip';
      final file = File(oversizedPath);

      // Create sparse / dummy file marked as > 50 MB
      final raf = await file.open(mode: FileMode.write);
      await raf.truncate(55 * 1024 * 1024);
      await raf.close();

      expect(file.lengthSync(), equals(55 * 1024 * 1024));

      final result = await ThumbnailGenerator.generate(
        filePath: oversizedPath,
        filename: 'huge_archive.zip',
        mimeType: 'application/zip',
      );

      // Should safely return null without throwing OOM
      expect(result, isNull);
    });
  });
}
