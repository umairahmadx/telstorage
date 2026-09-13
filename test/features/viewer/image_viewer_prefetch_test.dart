/*
 * File: image_viewer_prefetch_test.dart
 * Description: Automated test verifying that opening ImageViewerScreen only downloads the active image immediately, delaying adjacent prefetch by 2 seconds.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/download_queue_service.dart';
import 'package:telstorage/core/services/download_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/thumbnail_repository.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/image_viewer/image_viewer_screen.dart';

class _MockTelegramService extends TelegramService {
  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    RequestPriority priority = RequestPriority.normal,
  ]) async {
    return Uint8List.fromList([1, 2, 3, 4]);
  }
}

class _MockDownloadService extends DownloadService {
  final List<String> requestedFileIds = [];

  _MockDownloadService(super.telegram);

  @override
  Future<Uint8List> downloadFile(
    FileRecord record,
    void Function(double progress, String status)? onProgress, {
    RequestPriority priority = RequestPriority.normal,
  }) async {
    requestedFileIds.add(record.fileId);
    return Uint8List.fromList([1, 2, 3, 4]);
  }
}

class _MockDownloadQueueService extends DownloadQueueService {
  _MockDownloadQueueService(super.downloadService, super.boxName);

  @override
  String? getCompletedPath(String fileId) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  late Directory tempDir;
  late _MockTelegramService mockTelegram;
  late _MockDownloadService mockDownload;
  late ThemeData testTheme;

  final sampleImages = [
    FileRecord(
      fileId: 'img_01',
      name: 'photo_1.jpg',
      metadataMessageId: 101,
      sizeMb: 1.0,
      mimeType: 'image/jpeg',
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: 'hash_01',
    ),
    FileRecord(
      fileId: 'img_02',
      name: 'photo_2.jpg',
      metadataMessageId: 102,
      sizeMb: 1.0,
      mimeType: 'image/jpeg',
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: 'hash_02',
    ),
    FileRecord(
      fileId: 'img_03',
      name: 'photo_3.jpg',
      metadataMessageId: 103,
      sizeMb: 1.0,
      mimeType: 'image/jpeg',
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: 'hash_03',
    ),
  ];

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('viewer_prefetch_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );

    mockTelegram = _MockTelegramService();
    mockDownload = _MockDownloadService(mockTelegram);

    ServiceLocator.instance.setInitializedForTesting(true);
    ServiceLocator.instance.setDownloadServiceForTesting(mockDownload);
    ServiceLocator.instance.setDownloadQueueForTesting(_MockDownloadQueueService(mockDownload, 'mock_box'));
    ServiceLocator.instance.setThumbnailRepositoryForTesting(ThumbnailRepository(mockTelegram));

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
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets(
    'TC-PREFETCH-01: Opening ImageViewerScreen downloads ONLY the active image immediately; adjacent images wait for 2s rest',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: ImageViewerScreen(
            images: sampleImages,
            initialIndex: 1, // Opens on img_02
          ),
        ),
      );

      // Settle initial build microtasks
      await tester.pump();

      // Assert that on initial open, ONLY the active image img_02 is requested
      expect(mockDownload.requestedFileIds.contains('img_01'), isFalse,
          reason: 'Previous image img_01 must NOT be requested immediately on open');
      expect(mockDownload.requestedFileIds.contains('img_03'), isFalse,
          reason: 'Next image img_03 must NOT be requested immediately on open');
      expect(mockDownload.requestedFileIds, ['img_02'],
          reason: 'Only the active image img_02 should be downloaded on open');

      // Now advance timer by 2 seconds of resting on the image
      await tester.pump(const Duration(seconds: 2));

      // After resting 2 seconds, adjacent prefetching should be triggered
      expect(mockDownload.requestedFileIds.contains('img_03'), isTrue,
          reason: 'Next image img_03 should be prefetched after 2s resting debounce');
    },
  );
}
