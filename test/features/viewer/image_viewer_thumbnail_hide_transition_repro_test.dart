/*
 * File: image_viewer_thumbnail_hide_transition_repro_test.dart
 * Description: Automated reproduction test verifying that the thumbnail is cleanly hidden once the full-resolution image loads and 0-byte corrupt files are rejected.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/image_viewer_cache_service.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/image_viewer/widgets/image_zoom_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ThemeData testTheme;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('thumb_transition_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );

    testTheme = ThemeData(
      brightness: Brightness.dark,
      extensions: const [
        AppColorsExtension(
          bgPrimary: AppColors.black,
          bgSurface: AppColors.grey900,
          bgSurfaceInset: AppColors.grey800,
          borderSubtle: AppColors.grey800,
          textPrimary: AppColors.white,
          textSecondary: AppColors.grey600,
          textTertiary: AppColors.grey700,
          accentPrimary: AppColors.white,
          filePdf: AppColors.filePdf,
          fileVideo: AppColors.fileVideo,
          fileZip: AppColors.fileZip,
          fileFolder: AppColors.fileFolder,
          fileFolderBg: AppColors.fileFolderBgDark,
          filePalette: AppColors.filePalette,
          fileVideoBg: AppColors.grey800,
          fileTextBg: AppColors.grey800,
          fileGenericBg: AppColors.grey800,
          filePdfBg: AppColors.filePdfBgDark,
          glowColor: AppColors.glowDark,
          heroGradient: [AppColors.black, AppColors.grey900],
          primaryGradient: [AppColors.white, AppColors.white],
          selectionColor: AppColors.grey800,
          selectionColorAlt: AppColors.grey800,
          success: AppColors.success,
          error: AppColors.error,
          warning: AppColors.warning,
        ),
      ],
    );
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Thumbnail to Full-Resolution Transition Tests', () {
    testWidgets('TC-TRANSITION-REPRO: Thumbnail is unmounted/hidden once full-resolution image finishes loading',
        (tester) async {
      final file = FileRecord(
        fileId: 'img_test_transition',
        name: 'photo_high_res.jpg',
        metadataMessageId: 101,
        sizeMb: 4.5,
        mimeType: 'image/jpeg',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'hash_transition',
        thumbnailFileId: 'thumb_transition',
      );

      // Create a valid full-res JPEG file in local image cache
      final cacheDir = Directory('${tempDir.path}/image_cache');
      cacheDir.createSync(recursive: true);
      final cacheTarget = File('${cacheDir.path}/${file.fileId}.jpg');
      final dummyImg = img.Image(width: 80, height: 80);
      img.fill(dummyImg, color: img.ColorRgb8(50, 150, 250));
      cacheTarget.writeAsBytesSync(img.encodeJpg(dummyImg));

      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: Scaffold(
            body: ImageZoomPage(
              file: file,
              isActive: true,
            ),
          ),
        ),
      );

      // Allow async cache load to complete
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      // The full resolution image must be present
      expect(find.byType(Image), findsOneWidget,
          reason: 'Only the full-resolution Image should be mounted once loaded; thumbnail should be hidden');

      // The placeholder thumbnail icon must not be in the tree
      expect(find.byIcon(Icons.image_outlined), findsNothing,
          reason: 'Placeholder thumbnail icon should be hidden/unmounted when full-resolution is ready');
    });

    test('TC-CACHE-0-BYTE-REPRO: getCachedImageFile rejects and cleans 0-byte corrupt file', () async {
      final file = FileRecord(
        fileId: 'corrupted_zero_byte',
        name: 'corrupted.jpg',
        metadataMessageId: 102,
        sizeMb: 1.0,
        mimeType: 'image/jpeg',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'hash_corrupt',
      );

      final cacheDir = Directory('${tempDir.path}/image_cache');
      cacheDir.createSync(recursive: true);
      final cacheTarget = File('${cacheDir.path}/${file.fileId}.jpg');
      // Create empty 0-byte file
      cacheTarget.writeAsBytesSync([]);
      expect(cacheTarget.existsSync(), isTrue);
      expect(cacheTarget.lengthSync(), equals(0));

      final cached = await ImageViewerCacheService.instance.getCachedImageFile(file);

      // Must reject 0-byte files and delete them so full resolution can be fetched
      expect(cached, isNull, reason: '0-byte files must not be returned as valid cache hits');
      expect(cacheTarget.existsSync(), isFalse, reason: '0-byte corrupt file should be automatically purged');
    });
  });
}
