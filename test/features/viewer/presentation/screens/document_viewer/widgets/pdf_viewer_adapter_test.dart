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
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/widgets/pdf_selection_controls.dart';
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

  /// Builds and pumps [PdfViewerAdapter] for a PDF record and returns the
  /// [PdfViewer] widget that the production adapter handed to pdfrx.
  Future<PdfViewer> pumpAdapter(WidgetTester tester) async {
    final record = FileRecord(
      fileId: 'pdf-selection',
      name: 'selection.pdf',
      metadataMessageId: 2,
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

    return tester.widget<PdfViewer>(find.byType(PdfViewer));
  }

  testWidgets(
      'PDF viewer keeps selection handles enabled so one-finger drag scrolls',
      (tester) async {
    // pdfrx wires onPanStart/onPanUpdate/onPanEnd on the text layer whenever
    // enableSelectionHandles is false (pdfrx-2.2.24
    // lib/src/widgets/pdf_viewer.dart:532-534). That claims the touch pan
    // before the InteractiveViewer can, so one-finger drag selects text
    // instead of scrolling. Omitting the flag restores pdfrx's per-device
    // default: handles on touch, drag-to-select on mouse.
    final selection = (await pumpAdapter(tester)).params.textSelectionParams;

    expect(
      selection?.enableSelectionHandles ?? true,
      isTrue,
      reason: 'enableSelectionHandles: false disables handles and turns '
          'one-finger drag into drag-to-select instead of scrolling.',
    );
    expect(
      selection?.showContextMenuAutomatically,
      isTrue,
      reason: 'Handles mode needs the automatic context menu for Copy.',
    );
  });

  testWidgets(
      'PDF selection draws Android teardrop handles instead of pdfrx triangles',
      (tester) async {
    final viewer = await pumpAdapter(tester);

    // pdfrx only leaves its default grey right-triangle handles when these are
    // unset: the builder falls back at pdf_viewer.dart:2315, and the placement
    // offset at 2323/2346. Both must be wired for the swap to take effect.
    expect(
      viewer.params.textSelectionParams?.buildSelectionHandle,
      isNotNull,
      reason: 'Without a custom builder pdfrx paints grey triangles.',
    );
    expect(
      viewer.params.textSelectionParams?.calcSelectionHandleOffset,
      isNotNull,
      reason: 'The Material glyph carries its tip on the box top edge, so pdfrx '
          'needs the offset that puts it back on the anchored corner.',
    );
  });

  testWidgets('PDF selection colors stay scoped to the viewer subtree',
      (tester) async {
    await pumpAdapter(tester);

    // pdfrx has no selection color params; it reads TextSelectionTheme from the
    // viewer subtree, so the tint has to be applied by an ancestor of it.
    expect(
      find.ancestor(
        of: find.byType(PdfViewer),
        matching: find.byType(PdfSelectionColorScope),
      ),
      findsOneWidget,
    );

    final theme = tester.widget<TextSelectionTheme>(
      find
          .ancestor(
            of: find.byType(PdfViewer),
            matching: find.byType(TextSelectionTheme),
          )
          .first,
    );
    expect(theme.data.selectionHandleColor, AppColors.primary);
    expect(
      theme.data.selectionColor,
      AppColors.primary.withValues(alpha: 0.35),
      reason: 'AppTheme primary is white/black, which is why pdfrx\'s default '
          'highlight looks like a grey wash.',
    );
  });
}
