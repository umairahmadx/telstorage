/*
 * File: image_viewer_progressive_swap_test.dart
 * Description: Reproduction tests for seamless progressive image swapping without black dip and zero-delay HEIC handling.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/core/utils/media_preview_helper.dart';
import 'package:telstorage/features/viewer/presentation/screens/image_viewer/widgets/image_zoom_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late ThemeData testTheme;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('swap_test_');
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
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Progressive Image Swapping Reproduction Tests', () {
    test('TC-SWAP-01: HEIC / HEIF bypasses embedded JPEG scanner with 0 delay', () async {
      // Simulate an HEIC file payload (e.g. ftyp heic header)
      final heicData = Uint8List(1024);
      heicData[4] = 0x66; // 'f'
      heicData[5] = 0x74; // 't'
      heicData[6] = 0x79; // 'y'
      heicData[7] = 0x70; // 'p'
      heicData[8] = 0x68; // 'h'
      heicData[9] = 0x65; // 'e'
      heicData[10] = 0x69; // 'i'
      heicData[11] = 0x63; // 'c'

      final stopwatch = Stopwatch()..start();
      final result = await MediaPreviewHelper.prepareViewableBytes(
        rawBytes: heicData,
        filename: 'IMG_2026.heic',
      );
      stopwatch.stop();

      // Must return immediately without scanning or attempting JPEG extract
      expect(result, equals(heicData));
      expect(stopwatch.elapsedMilliseconds, lessThan(300),
          reason: 'HEIC must not spend time scanning for embedded JPEG stream');
    });

    testWidgets('TC-SWAP-02: ImageZoomPage retains thumbnail while full-res image is decoding',
        (tester) async {
      final file = FileRecord(
        fileId: 'img_test_swap',
        name: 'vacation.jpg',
        metadataMessageId: 10,
        sizeMb: 2.0,
        mimeType: 'image/jpeg',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'hash_test',
        thumbnailFileId: 'thumb_test',
      );

      // Create a cached full-res file in cache directory synchronously
      final cacheDir = Directory('${tempDir.path}/image_cache');
      cacheDir.createSync(recursive: true);
      final cacheTarget = File('${cacheDir.path}/${file.fileId}.jpg');
      final dummyImg = img.Image(width: 100, height: 100);
      img.fill(dummyImg, color: img.ColorRgb8(100, 200, 150));
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

      // Advance clock so local cache check loads file
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();

      // Look at the widget tree structure:
      // The full-res Image widget must have a frameBuilder configured so that during decoding,
      // the thumbnail remains in the tree instead of being completely destroyed.
      final fullImageFinder = find.byType(Image);
      expect(fullImageFinder, findsWidgets);

      final fullImageWidget = tester.widget<Image>(fullImageFinder.first);
      expect(fullImageWidget.frameBuilder, isNotNull,
          reason: 'Image widget must configure frameBuilder to prevent black dip during async decode');
    });
  });
}
