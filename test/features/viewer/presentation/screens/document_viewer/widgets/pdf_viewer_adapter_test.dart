/*
 * File: pdf_viewer_adapter_test.dart
 * Description: Widget test for PdfViewerAdapter initialization and placeholder rendering.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/viewmodel/document_viewer_viewmodel.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/widgets/pdf_viewer_adapter.dart';

void main() {
  testWidgets('PdfViewerAdapter renders without crashing', (tester) async {
    final record = FileRecord(
      fileId: 'pdf1',
      name: 'manual.pdf',
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
        home: Scaffold(
          body: PdfViewerAdapter(
            viewModel: vm,
            file: File('non_existent.pdf'),
          ),
        ),
      ),
    );

    expect(find.byType(PdfViewerAdapter), findsOneWidget);

    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(viewer.params.backgroundColor, AppColors.black);
    expect(viewer.params.pageDropShadow, isNull);
    expect(viewer.params.scrollPhysics, isA<ClampingScrollPhysics>());
    expect(viewer.params.panAxis, PanAxis.free);
    expect(viewer.params.pageAnchor, PdfPageAnchor.center);
  });
}
