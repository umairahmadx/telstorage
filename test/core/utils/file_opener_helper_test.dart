/*
 * File: file_opener_helper_test.dart
 * Description: Unit tests for FileOpenerHelper covering MIME type resolution, extension fallbacks, and error resilience.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/utils/file_opener_helper.dart';

void main() {
  group('FileOpenerHelper.resolveMimeType', () {
    test('TC-01: Returns explicit valid MIME type when provided', () {
      final mime = FileOpenerHelper.resolveMimeType(
        mimeType: 'image/png',
        fileName: 'photo.jpg',
      );
      expect(mime, equals('image/png'));
    });

    test('TC-02: Ignores application/octet-stream and resolves by filename', () {
      final mime = FileOpenerHelper.resolveMimeType(
        mimeType: 'application/octet-stream',
        fileName: 'document.pdf',
      );
      expect(mime, equals('application/pdf'));
    });

    test('TC-03: Resolves standard image extensions correctly', () {
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'photo.jpg'),
        equals('image/jpeg'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'vector.png'),
        equals('image/png'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'animated.gif'),
        equals('image/gif'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'image.webp'),
        equals('image/webp'),
      );
    });

    test('TC-04: Resolves video extensions correctly', () {
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'movie.mp4'),
        equals('video/mp4'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'clip.mkv'),
        equals('video/x-matroska'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'quick.mov'),
        equals('video/quicktime'),
      );
    });

    test('TC-05: Resolves custom extension mappings', () {
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'raw_photo.heic'),
        equals('image/heic'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'raw_photo.heif'),
        equals('image/heif'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'app.apk'),
        equals('application/vnd.android.package-archive'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'book.epub'),
        equals('application/epub+zip'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'readme.md'),
        equals('text/markdown'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'config.yaml'),
        equals('text/yaml'),
      );
      expect(
        FileOpenerHelper.resolveMimeType(fileName: 'archive.7z'),
        equals('application/x-7z-compressed'),
      );
    });

    test('TC-06: Falls back to wildcard "*/*" for files with NO extension', () {
      final mime = FileOpenerHelper.resolveMimeType(fileName: 'LICENSE');
      expect(mime, equals('*/*'));
    });

    test('TC-07: Falls back to wildcard "*/*" for unknown extensions', () {
      final mime = FileOpenerHelper.resolveMimeType(
        fileName: 'strange_blob.unknownext123',
      );
      expect(mime, equals('*/*'));
    });

    test('TC-08: Falls back to wildcard "*/*" when no information is provided', () {
      final mime = FileOpenerHelper.resolveMimeType();
      expect(mime, equals('*/*'));
    });
  });

  group('FileOpenerHelper.openFile validation', () {
    test('TC-09: Returns false immediately for empty file path', () async {
      final result = await FileOpenerHelper.openFile(null, filePath: '');
      expect(result, isFalse);
    });

    test('TC-10: Returns false and handles missing file without throwing', () async {
      final result = await FileOpenerHelper.openFile(
        null,
        filePath: '/non/existent/path/to/missing_file.jpg',
      );
      expect(result, isFalse);
    });
  });
}
