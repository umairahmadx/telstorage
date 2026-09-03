/*
 * File: image_viewer_cache_service_test.dart
 * Description: Unit tests verifying image identification, cache target path resolution, and LRU touch timestamp updates.
 */

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/image_viewer_cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('image_viewer_cache_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ImageViewerCacheService Unit Tests', () {
    test('TC-01: isImageRecord validates image MIME types and extensions', () {
      final imgJpg = FileRecord(
        fileId: 'img1',
        name: 'photo.jpg',
        metadataMessageId: 1,
        sizeMb: 1.2,
        mimeType: 'image/jpeg',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'hash1',
      );

      final imgPngNoMime = FileRecord(
        fileId: 'img2',
        name: 'screenshot.PNG',
        metadataMessageId: 2,
        sizeMb: 2.0,
        mimeType: '',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'hash2',
      );

      final pdfDoc = FileRecord(
        fileId: 'doc1',
        name: 'manual.pdf',
        metadataMessageId: 3,
        sizeMb: 3.5,
        mimeType: 'application/pdf',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'hash3',
      );

      final videoFile = FileRecord(
        fileId: 'vid1',
        name: 'video.mp4',
        metadataMessageId: 4,
        sizeMb: 10.0,
        mimeType: 'video/mp4',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'hash4',
      );

      expect(ImageViewerCacheService.isImageRecord(imgJpg), isTrue);
      expect(ImageViewerCacheService.isImageRecord(imgPngNoMime), isTrue);
      expect(ImageViewerCacheService.isImageRecord(pdfDoc), isFalse);
      expect(ImageViewerCacheService.isImageRecord(videoFile), isFalse);
    });

    test('TC-02: getCacheTargetFile resolves path under image_cache partition', () async {
      final service = ImageViewerCacheService.instance;
      final file = FileRecord(
        fileId: 'test_file_123',
        name: 'vacation.webp',
        metadataMessageId: 10,
        sizeMb: 1.5,
        mimeType: 'image/webp',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'hash',
      );

      final targetFile = await service.getCacheTargetFile(file);
      expect(targetFile.path, contains('image_cache'));
      expect(targetFile.path, endsWith('test_file_123.webp'));
      expect(targetFile.parent.existsSync(), isTrue);
    });

    test('TC-03: getCachedImageFile touches lastModified timestamp on cache hit (LRU Touch)', () async {
      final service = ImageViewerCacheService.instance;
      final file = FileRecord(
        fileId: 'lru_file_456',
        name: 'landscape.jpg',
        metadataMessageId: 11,
        sizeMb: 2.1,
        mimeType: 'image/jpeg',
        uploadedAt: DateTime(2026, 1, 1),
        chunkCount: 1,
        sha256Hash: 'hash',
      );

      // Initially not cached
      final initialCheck = await service.getCachedImageFile(file);
      expect(initialCheck, isNull);

      // Create simulated cached file with older timestamp
      final targetFile = await service.getCacheTargetFile(file);
      final pastTime = DateTime.now().subtract(const Duration(hours: 2));
      await targetFile.writeAsBytes([1, 2, 3, 4], flush: true);
      targetFile.setLastModifiedSync(pastTime);

      expect(targetFile.lastModifiedSync().isBefore(DateTime.now().subtract(const Duration(minutes: 90))), isTrue);

      // Now query getCachedImageFile
      final hitFile = await service.getCachedImageFile(file);
      expect(hitFile, isNotNull);
      expect(hitFile!.existsSync(), isTrue);

      // Verify that LRU touch refreshed the lastModified to near now
      final touchedTime = hitFile.lastModifiedSync();
      expect(touchedTime.difference(pastTime).inMinutes, greaterThan(60));
    });
  });
}
