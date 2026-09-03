/*
 * File: image_viewer_screen_test.dart
 * Description: Widget tests for ImageViewerScreen verifying initial index, swipe navigation, immersive mode toggling, and UI actions.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/image_viewer/image_viewer_screen.dart';
import 'package:telstorage/features/viewer/presentation/screens/image_viewer/widgets/image_viewer_bottom_bar.dart';
import 'package:telstorage/features/viewer/presentation/screens/image_viewer/widgets/image_viewer_top_bar.dart';
import 'package:telstorage/features/viewer/presentation/screens/image_viewer/widgets/image_zoom_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  late Directory tempDir;
  late ThemeData testTheme;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('image_viewer_widget_test_');
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
      await tempDir.delete(recursive: true);
    }
  });

  final sampleImages = [
    FileRecord(
      fileId: 'img_01',
      name: 'vacation_beach.jpg',
      metadataMessageId: 101,
      sizeMb: 2.4,
      mimeType: 'image/jpeg',
      uploadedAt: DateTime(2026, 6, 15, 10, 30),
      chunkCount: 1,
      sha256Hash: 'hash_01',
    ),
    FileRecord(
      fileId: 'img_02',
      name: 'mountain_sunset.png',
      metadataMessageId: 102,
      sizeMb: 4.1,
      mimeType: 'image/png',
      uploadedAt: DateTime(2026, 6, 16, 18, 45),
      chunkCount: 2,
      sha256Hash: 'hash_02',
    ),
    FileRecord(
      fileId: 'img_03',
      name: 'family_gathering.webp',
      metadataMessageId: 103,
      sizeMb: 1.8,
      mimeType: 'image/webp',
      uploadedAt: DateTime(2026, 6, 17, 14, 00),
      chunkCount: 1,
      sha256Hash: 'hash_03',
    ),
  ];

  Widget buildTestViewer({int initialIndex = 0}) {
    return MaterialApp(
      theme: testTheme,
      home: ImageViewerScreen(
        images: sampleImages,
        initialIndex: initialIndex,
      ),
    );
  }

  group('ImageViewerScreen Widget Tests', () {
    testWidgets('TC-01: Displays initial image and counter accurately',
        (tester) async {
      await tester.pumpWidget(buildTestViewer(initialIndex: 1));
      await tester.pump();

      // Verify that image 2 of 3 is displayed
      expect(find.text('mountain_sunset.png'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      expect(find.text(sampleImages[1].formattedSize), findsOneWidget);

      // Verify TopBar and BottomBar are visible
      expect(find.byType(ImageViewerTopBar), findsOneWidget);
      expect(find.byType(ImageViewerBottomBar), findsOneWidget);
    });

    testWidgets('TC-02: Swiping horizontally updates active image and counter',
        (tester) async {
      await tester.pumpWidget(buildTestViewer(initialIndex: 0));
      await tester.pump();

      expect(find.text('vacation_beach.jpg'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);

      // Swipe left to transition to next image
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('mountain_sunset.png'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
    });

    testWidgets('TC-03: Single tap toggles toolbar visibility (Immersive Mode)',
        (tester) async {
      await tester.pumpWidget(buildTestViewer(initialIndex: 0));
      await tester.pump();

      // Initially visible
      expect(
        tester.widget<ImageViewerTopBar>(find.byType(ImageViewerTopBar)).isVisible,
        isTrue,
      );

      // Tap on viewport (pump double-tap delay)
      await tester.tap(find.byType(PageView));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Toolbars should now be toggled to hidden
      expect(
        tester.widget<ImageViewerTopBar>(find.byType(ImageViewerTopBar)).isVisible,
        isFalse,
      );

      // Tap again to restore
      await tester.tap(find.byType(PageView));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ImageViewerTopBar>(find.byType(ImageViewerTopBar)).isVisible,
        isTrue,
      );
    });

    testWidgets('TC-04: Back button closes ImageViewerScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => ImageViewerScreen.open(
                  context,
                  images: sampleImages,
                  initialIndex: 0,
                ),
                child: const Text('Open Viewer'),
              ),
            ),
          ),
        ),
      );

      // Open viewer
      await tester.tap(find.text('Open Viewer'));
      await tester.pumpAndSettle();

      expect(find.byType(ImageViewerScreen), findsOneWidget);

      // Tap back button
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // ImageViewerScreen should be dismissed
      expect(find.byType(ImageViewerScreen), findsNothing);
      expect(find.text('Open Viewer'), findsOneWidget);
    });

    testWidgets('TC-05: Bottom bar renders Download and Share buttons side-by-side without labels',
        (tester) async {
      await tester.pumpWidget(buildTestViewer(initialIndex: 0));
      await tester.pump();

      // Ensure old label is gone
      expect(find.text('Save to Device'), findsNothing);

      // Verify download and share icons are present in bottom bar
      final bottomBar = find.byType(ImageViewerBottomBar);
      expect(bottomBar, findsOneWidget);

      expect(
        find.descendant(of: bottomBar, matching: find.byIcon(AppIcons.download)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bottomBar, matching: find.byIcon(AppIcons.share)),
        findsOneWidget,
      );
    });

    testWidgets('TC-06: PageView pages have horizontal padding creating image gutter',
        (tester) async {
      await tester.pumpWidget(buildTestViewer(initialIndex: 0));
      await tester.pump();

      // Check for horizontal padding wrapping ImageZoomPage
      final paddingFinder = find.ancestor(
        of: find.byType(ImageZoomPage).first,
        matching: find.byType(Padding),
      );
      expect(paddingFinder, findsWidgets);

      final paddingWidget = tester.widget<Padding>(paddingFinder.first);
      expect(paddingWidget.padding, const EdgeInsets.symmetric(horizontal: 8.0));
    });

    testWidgets('TC-07: ImageZoomPage does not render bottom status pill or text',
        (tester) async {
      await tester.pumpWidget(buildTestViewer(initialIndex: 0));
      await tester.pump();

      // No status text pill or text should appear
      expect(find.text('Reading file index…'), findsNothing);
      expect(find.text('Loading…'), findsNothing);
      expect(find.text('Ready'), findsNothing);
    });
  });
}
