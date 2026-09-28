/*
 * File: office_fallback_card_test.dart
 * Description: Widget test for OfficeFallbackCard action buttons and metadata display.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/widgets/office_fallback_card.dart';

void main() {
  testWidgets('OfficeFallbackCard displays filename and action buttons',
      (tester) async {
    final record = FileRecord(
      fileId: 'office1',
      name: 'Presentation.pptx',
      metadataMessageId: 1,
      sizeMb: 4.5,
      mimeType:
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: 'h',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: OfficeFallbackCard(
            file: record,
            localFile: File('mock.pptx'),
          ),
        ),
      ),
    );

    expect(find.text('Presentation.pptx'), findsOneWidget);
    expect(find.text('Open with Device App'), findsOneWidget);
  });
}
