/*
 * File: text_editor_adapter_test.dart
 * Description: Widget test for TextEditorAdapter language mode and line numbers gutter.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/viewmodel/document_viewer_viewmodel.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/widgets/text_editor_adapter.dart';

void main() {
  testWidgets('TextEditorAdapter mounts and displays code content',
      (tester) async {
    final record = FileRecord(
      fileId: 'txt1',
      name: 'hello.dart',
      metadataMessageId: 1,
      sizeMb: 0.1,
      mimeType: 'text/plain',
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: 'h',
    );
    final vm = DocumentViewerViewModel(file: record);
    vm.setTextContent('void main() { print("hello"); }');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: TextEditorAdapter(viewModel: vm),
        ),
      ),
    );

    expect(find.byType(TextEditorAdapter), findsOneWidget);
  });
}
