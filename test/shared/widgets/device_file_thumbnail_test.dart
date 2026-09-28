/*
 * File: device_file_thumbnail_test.dart
 * Description: Automated tests for DeviceFileThumbnail verifying image thumbnail rendering,
 * category icon fallbacks, and tap-to-open callback execution.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/device_file_picker/device_file_thumbnail.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('DeviceFileThumbnail Tests', () {
    testWidgets('Renders image thumbnail and triggers onOpen on tap',
        (tester) async {
      bool opened = false;
      const testImagePath = 'test_assets/sample.png';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: DeviceFileThumbnail(
              filePath: testImagePath,
              fileName: 'sample.png',
              icon: AppIcons.fileImage,
              iconColor: Colors.blue,
              onOpen: () => opened = true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Expect Image.file widget is rendered for image files
      expect(find.byType(Image), findsOneWidget);

      // Tap thumbnail
      await tester.tap(find.byType(DeviceFileThumbnail));
      await tester.pump();

      expect(opened, isTrue,
          reason: 'Tapping thumbnail must trigger onOpen callback');
    });

    testWidgets('Renders fallback icon for generic file and triggers onOpen on tap',
        (tester) async {
      bool opened = false;
      const testDocPath = 'documents/notes.txt';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: DeviceFileThumbnail(
              filePath: testDocPath,
              fileName: 'notes.txt',
              icon: AppIcons.fileGeneric,
              iconColor: Colors.grey,
              onOpen: () => opened = true,
            ),
          ),
        ),
      );
      await tester.pump();

      // Expect fallback icon is rendered
      expect(find.byIcon(AppIcons.fileGeneric), findsOneWidget);

      // Tap thumbnail
      await tester.tap(find.byType(DeviceFileThumbnail));
      await tester.pump();

      expect(opened, isTrue,
          reason: 'Tapping thumbnail must trigger onOpen callback');
    });
  });
}
