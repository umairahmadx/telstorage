/*
 * File: share_link_sheet_test.dart
 * Description: Widget tests verifying dynamic Get URL / Copy Link buttons, QR button visibility, and ThumbnailWidget integration in ShareLinkSheet.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
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

  group('ShareLinkSheet Dynamic State & Thumbnail Tests', () {
    testWidgets('TC-01: Displays "Get URL" and hides QR button when no active share exists', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ShareLinkSheet(
              file: testFile,
              shareUrl: null,
              onCopyLink: (_, __, ___) {},
            ),
          ),
        ),
      );

      // Verify ThumbnailWidget is rendered
      expect(find.byType(ThumbnailWidget), findsOneWidget);
      expect(find.text('vacation_photo.jpg'), findsOneWidget);

      // Verify Get URL button is present
      expect(find.text('Get URL'), findsOneWidget);
      expect(find.text('Copy Link'), findsNothing);

      // Verify QR button icon is not rendered
      expect(find.byIcon(AppIcons.qrCode), findsNothing);
    });

    testWidgets('TC-02: Displays "Copy Link" and shows QR button when active share exists', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ShareLinkSheet(
              file: testFile,
              shareUrl: 'https://storage.to/v/my-custom-photo',
              onCopyLink: (_, __, ___) {},
            ),
          ),
        ),
      );

      // Verify ThumbnailWidget is rendered
      expect(find.byType(ThumbnailWidget), findsOneWidget);

      // Verify Copy Link button is present
      expect(find.text('Copy Link'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Delete Link (Expire Now)'), findsOneWidget);
      expect(find.text('Get URL'), findsNothing);

      // Verify active link card displays URL
      expect(find.text('https://storage.to/v/my-custom-photo'), findsOneWidget);

      // Verify QR button icon is rendered
      expect(find.byIcon(AppIcons.qrCode), findsOneWidget);
    });
  });
}
