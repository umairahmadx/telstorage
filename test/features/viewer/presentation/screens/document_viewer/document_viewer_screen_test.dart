/*
 * File: document_viewer_screen_test.dart
 * Description: Widget tests verifying DocumentViewerScreen route rendering, loading state, and adapter delegation.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/document_viewer_screen.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/viewmodel/document_viewer_viewmodel.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/widgets/office_fallback_card.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/widgets/text_editor_adapter.dart';

void main() {
  group('DocumentViewerScreen Widget Tests', () {
    testWidgets('renders loading indicator when document is loading',
        (tester) async {
      final record = FileRecord(
        fileId: 'doc1',
        name: 'terms.pdf',
        metadataMessageId: 1,
        sizeMb: 1.0,
        mimeType: 'application/pdf',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'h',
      );

      final vm = DocumentViewerViewModel(file: record);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: DocumentViewerScreen(
            file: record,
            viewModel: vm,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders TextEditorAdapter for text files', (tester) async {
      final record = FileRecord(
        fileId: 'txt1',
        name: 'notes.txt',
        metadataMessageId: 2,
        sizeMb: 0.1,
        mimeType: 'text/plain',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'h',
      );

      final vm = DocumentViewerViewModel(file: record);
      final tempFile = File('${Directory.systemTemp.path}/test_screen_note.txt')
        ..writeAsStringSync('Hello Screen');
      vm.setLoadedForTest(tempFile, 'Hello Screen');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: DocumentViewerScreen(
            file: record,
            viewModel: vm,
          ),
        ),
      );

      expect(find.byType(TextEditorAdapter), findsOneWidget);

      if (tempFile.existsSync()) tempFile.deleteSync();
    });

    testWidgets('renders OfficeFallbackCard for office documents',
        (tester) async {
      final record = FileRecord(
        fileId: 'doc_office',
        name: 'sheet.xlsx',
        metadataMessageId: 3,
        sizeMb: 2.0,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'h',
      );

      final vm = DocumentViewerViewModel(file: record);
      final tempFile = File('${Directory.systemTemp.path}/test_sheet.xlsx')
        ..writeAsStringSync('dummy');
      vm.setLoadedForTest(tempFile, '');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: DocumentViewerScreen(
            file: record,
            viewModel: vm,
          ),
        ),
      );

      expect(find.byType(OfficeFallbackCard), findsOneWidget);

      if (tempFile.existsSync()) tempFile.deleteSync();
    });
  });
}
