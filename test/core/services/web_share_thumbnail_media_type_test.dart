/*
 * File: web_share_thumbnail_media_type_test.dart
 * Description: Unit tests verifying MIME type and filename resolution for web share thumbnail uploads.
 */

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/web_share_api_client.dart';

void main() {
  group('WebShareApiClient.resolveImageMediaType Magic-Byte Resolution', () {
    test('TC-01: JPEG magic bytes resolve to image/jpeg and thumbnail.jpg', () {
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      final result = WebShareApiClient.resolveImageMediaType(jpegBytes);

      expect(result.mediaType.type, equals('image'));
      expect(result.mediaType.subtype, equals('jpeg'));
      expect(result.filename, equals('thumbnail.jpg'));
    });

    test('TC-02: PNG magic bytes resolve to image/png and thumbnail.png', () {
      final pngBytes = Uint8List.fromList(
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00]);
      final result = WebShareApiClient.resolveImageMediaType(pngBytes);

      expect(result.mediaType.type, equals('image'));
      expect(result.mediaType.subtype, equals('png'));
      expect(result.filename, equals('thumbnail.png'));
    });

    test('TC-03: WebP magic bytes resolve to image/webp and thumbnail.webp', () {
      final webpBytes = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // 'RIFF'
        0x20, 0x00, 0x00, 0x00, // file length
        0x57, 0x45, 0x42, 0x50, // 'WEBP'
        0x56, 0x50, 0x38, 0x20, // 'VP8 '
      ]);
      final result = WebShareApiClient.resolveImageMediaType(webpBytes);

      expect(result.mediaType.type, equals('image'));
      expect(result.mediaType.subtype, equals('webp'));
      expect(result.filename, equals('thumbnail.webp'));
    });

    test('TC-04: Arbitrary/unknown bytes fallback safely to image/jpeg', () {
      final randomBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      final result = WebShareApiClient.resolveImageMediaType(randomBytes);

      expect(result.mediaType.type, equals('image'));
      expect(result.mediaType.subtype, equals('jpeg'));
      expect(result.filename, equals('thumbnail.jpg'));
    });

    test('TC-05: Empty buffer safely returns fallback without throwing RangeError', () {
      final emptyBytes = Uint8List(0);
      final result = WebShareApiClient.resolveImageMediaType(emptyBytes);

      expect(result.mediaType.type, equals('image'));
      expect(result.mediaType.subtype, equals('jpeg'));
      expect(result.filename, equals('thumbnail.jpg'));
    });

    test('TC-06: Truncated 1-byte or 2-byte buffer safely returns fallback', () {
      final shortBytes = Uint8List.fromList([0xFF, 0xD8]);
      final result = WebShareApiClient.resolveImageMediaType(shortBytes);

      expect(result.mediaType.type, equals('image'));
      expect(result.mediaType.subtype, equals('jpeg'));
      expect(result.filename, equals('thumbnail.jpg'));
    });
  });
}
