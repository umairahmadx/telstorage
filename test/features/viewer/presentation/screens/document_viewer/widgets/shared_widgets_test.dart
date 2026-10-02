/*
 * File: shared_widgets_test.dart
 * Description: Widget tests for DocumentTopBar and DocumentPageScrubber.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/viewmodel/document_viewer_viewmodel.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/widgets/document_top_bar.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/widgets/document_page_scrubber.dart';

void main() {
  late FileRecord testFile;
  late DocumentViewerViewModel viewModel;

  setUp(() {
    testFile = FileRecord(
      fileId: '1',
      name: 'guide.pdf',
      metadataMessageId: 10,
      sizeMb: 2.5,
      mimeType: 'application/pdf',
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: 'hash',
    );
    viewModel = DocumentViewerViewModel(file: testFile);
  });

  testWidgets('DocumentTopBar displays filename and back button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: DocumentTopBar(
            viewModel: viewModel,
            onBack: () {},
            onToggleSearch: () {},
          ),
        ),
      ),
    );

    expect(find.text('guide.pdf'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('DocumentPageScrubber renders page count correctly', (tester) async {
    viewModel.setPage(3, total: 10);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: DocumentPageScrubber(
            viewModel: viewModel,
            onPageSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Page 3 of 10'), findsOneWidget);
  });
}
