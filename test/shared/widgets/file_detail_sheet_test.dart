/*
 * File: file_detail_sheet_test.dart
 * Description: Widget tests for FileDetailSheet verifying Download / Downloaded and Open action dynamics.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/dialogs/file_detail_sheet.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final testFile = FileRecord(
    fileId: 'file_001',
    metadataMessageId: 10,
    metadataFileId: 'meta_10',
    name: 'document.pdf',
    sizeMb: 1.5,
    mimeType: 'application/pdf',
    uploadedAt: DateTime(2026, 8, 26, 12, 0),
    chunkCount: 1,
    sha256Hash: 'hash123',
  );

  group('FileDetailSheet Downloaded & Open Button Tests', () {
    testWidgets('TC-01: Displays Download button when file is NOT downloaded', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: FileDetailSheet(
              file: testFile,
              isDownloaded: false,
              onShare: () {},
              onDownload: () {},
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Downloaded'), findsNothing);
      expect(find.text('Open'), findsNothing);
    });

    testWidgets('TC-02: Displays Downloaded and Open buttons when file is downloaded', (tester) async {
      bool openPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: FileDetailSheet(
              file: testFile,
              isDownloaded: true,
              localPath: '/downloads/document.pdf',
              onShare: () {},
              onDownload: () {},
              onOpen: () => openPressed = true,
              onRename: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      expect(find.text('Download'), findsNothing);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(openPressed, isTrue);
    });
  });
}
