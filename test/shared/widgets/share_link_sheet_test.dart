/*
 * File: share_link_sheet_test.dart
 * Description: Widget tests verifying 3-state ShareLinkSheet (Config, In-Progress, Active Hub), Max Downloads quota selector, and embedded ShareQrCard integration.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/dialogs/share_qr_card.dart';
import 'package:telstorage/shared/widgets/share_link_sheet.dart';
import 'package:telstorage/shared/widgets/thumbnail_widget.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final testFile = FileRecord(
    fileId: 'file_test_001',
    metadataMessageId: 100,
    metadataFileId: 'meta_001',
    name: 'vacation_photo.jpg',
    sizeMb: 4.2,
    mimeType: 'image/jpeg',
    uploadedAt: DateTime.now(),
    chunkCount: 1,
    sha256Hash: 'dummy_hash',
  );

  group('ShareLinkSheet Dynamic State & QR Tests', () {
    testWidgets(
        'TC-01: Displays "Generate Secure Link" and option selectors when no active share exists',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ShareLinkSheet(
              file: testFile,
              shareUrl: null,
              onGenerateLink: (_, __, ___, ____) {},
            ),
          ),
        ),
      );

      // Verify ThumbnailWidget is rendered
      expect(find.byType(ThumbnailWidget), findsOneWidget);
      expect(find.text('vacation_photo.jpg'), findsOneWidget);

      // Verify Generate button is present
      expect(find.text('Generate Secure Link'), findsOneWidget);
      expect(find.text('Copy Link'), findsNothing);

      // Verify option selectors: Expiry, Download Limit, Vanity Link
      expect(find.text('Expires'), findsOneWidget);
      expect(find.text('Download Limit'), findsOneWidget);
      expect(find.text('Custom Vanity Link (Optional)'), findsOneWidget);

      // Verify QR card is not rendered in config state
      expect(find.byType(ShareQrCard), findsNothing);
    });

    testWidgets(
        'TC-02: Displays "Copy Link", embedded ShareQrCard, and actions when active share exists',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ShareLinkSheet(
              file: testFile,
              shareUrl: 'https://storage.to/v/my-custom-photo',
              onGenerateLink: (_, __, ___, ____) {},
            ),
          ),
        ),
      );

      // Verify ThumbnailWidget is rendered
      expect(find.byType(ThumbnailWidget), findsOneWidget);

      // Verify Copy Link and Share buttons are present
      expect(find.text('Copy Link'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Delete Link (Expire Now)'), findsOneWidget);
      expect(find.text('Generate Secure Link'), findsNothing);

      // Verify active link card displays URL
      expect(find.text('https://storage.to/v/my-custom-photo'), findsOneWidget);

      // Verify embedded ShareQrCard is rendered with Save and Share buttons
      expect(find.byType(ShareQrCard), findsOneWidget);
      expect(find.text('Save QR'), findsOneWidget);
      expect(find.text('Share QR'), findsOneWidget);
    });

    testWidgets(
        'TC-03: Tapping Generate Secure Link transitions to in-sheet progress without popping',
        (tester) async {
      bool generated = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ShareLinkSheet(
              file: testFile,
              shareUrl: null,
              onGenerateLink: (pwd, expiry, slug, maxDownloads) {
                generated = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Generate Secure Link'), findsOneWidget);

      // Scroll into view and tap Generate button
      await tester.ensureVisible(find.text('Generate Secure Link'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate Secure Link'));
      await tester.pump();

      // Verify callback was invoked
      expect(generated, isTrue);

      // Verify in-sheet progress is shown
      expect(find.text('Cancel Share'), findsOneWidget);
      expect(find.text('Generate Secure Link'), findsNothing);
    });
  });
}
