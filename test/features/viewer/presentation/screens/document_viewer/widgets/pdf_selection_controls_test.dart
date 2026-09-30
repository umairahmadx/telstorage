/*
 * File: pdf_selection_controls_test.dart
 * Description: Tests for the Android-style PDF text-selection handles: glyph
 * mirroring, the anchor offset that puts the teardrop tip on the character
 * corner, zoom-aware sizing, and the brand-blue scope.
 */

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/features/viewer/presentation/screens/document_viewer/widgets/pdf_selection_controls.dart';

/// Character rectangle used by every anchor below: 8 wide, 10 tall.
const Rect _charRect = Rect.fromLTRB(10, 20, 18, 30);

PdfTextSelectionAnchor _anchor({
  required PdfTextSelectionAnchorType type,
  required PdfTextDirection direction,
}) =>
    PdfTextSelectionAnchor(
      _charRect,
      direction,
      type,
      const PdfPageText(
        pageNumber: 1,
        fullText: 'abc',
        charRects: [],
        fragments: [],
      ),
      0,
    );

TextSelectionHandleType _type(
  PdfTextSelectionAnchorType type,
  PdfTextDirection direction,
) =>
    PdfAndroidSelectionControls.handleTypeFor(type: type, direction: direction);

void main() {
  group('handleTypeFor', () {
    test('left-to-right gets the start glyph on A and the end glyph on B', () {
      expect(_type(PdfTextSelectionAnchorType.a, PdfTextDirection.ltr),
          TextSelectionHandleType.left);
      expect(_type(PdfTextSelectionAnchorType.b, PdfTextDirection.ltr),
          TextSelectionHandleType.right);
    });

    test('unknown direction matches pdfrx placement, which treats it as ltr',
        () {
      expect(_type(PdfTextSelectionAnchorType.a, PdfTextDirection.unknown),
          TextSelectionHandleType.left);
      expect(_type(PdfTextSelectionAnchorType.b, PdfTextDirection.unknown),
          TextSelectionHandleType.right);
    });

    test(
        'right-to-left mirrors the pair because pdfrx swaps the anchored corner',
        () {
      expect(_type(PdfTextSelectionAnchorType.a, PdfTextDirection.rtl),
          TextSelectionHandleType.right);
      expect(_type(PdfTextSelectionAnchorType.b, PdfTextDirection.rtl),
          TextSelectionHandleType.left);
    });

    test('vertical text mirrors too; there is no vertical teardrop to use', () {
      expect(_type(PdfTextSelectionAnchorType.a, PdfTextDirection.vrtl),
          TextSelectionHandleType.right);
      expect(_type(PdfTextSelectionAnchorType.b, PdfTextDirection.vrtl),
          TextSelectionHandleType.left);
    });
  });

  group('offsetFor', () {
    test('handle A drops by one box height so its tip meets the anchor', () {
      // pdfrx pins A with `bottom: viewHeight - rect.top - offset.dy`, i.e. the
      // box's bottom edge on the corner, while the glyph carries its tip on the
      // box's top edge.
      expect(
        PdfAndroidSelectionControls.offsetFor(PdfTextSelectionAnchorType.a),
        const Offset(0, kMaterialSelectionHandleSize),
      );
    });

    test('handle B is already pinned by the edge carrying its tip', () {
      expect(
        PdfAndroidSelectionControls.offsetFor(PdfTextSelectionAnchorType.b),
        Offset.zero,
      );
    });

    test('only the vertical axis moves; the horizontal one is already pinned',
        () {
      expect(
          PdfAndroidSelectionControls.offsetFor(PdfTextSelectionAnchorType.a).dx,
          0);
      expect(PdfAndroidSelectionControls.offsetFor(PdfTextSelectionAnchorType.b).dy,
          0);
    });
  });

  group('tipAlignment', () {
    test('names the corner MaterialTextSelectionControls anchors on', () {
      // getHandleAnchor: left -> (22, 0), right -> (0, 0).
      expect(
          PdfAndroidSelectionControls.tipAlignment(TextSelectionHandleType.left),
          Alignment.topRight);
      expect(
          PdfAndroidSelectionControls.tipAlignment(TextSelectionHandleType.right),
          Alignment.topLeft);
    });
  });

  group('sizeFor', () {
    test('tracks the on-screen character height', () {
      expect(
        PdfAndroidSelectionControls.sizeFor(charHeightOnScreen: 20, dragging: false),
        closeTo(23, 0.01),
      );
      expect(
        PdfAndroidSelectionControls.sizeFor(charHeightOnScreen: 30, dragging: false),
        closeTo(34.5, 0.01),
      );
    });

    test('never shrinks below a findable touch target', () {
      expect(
        PdfAndroidSelectionControls.sizeFor(charHeightOnScreen: 2, dragging: false),
        20,
      );
    });

    test('never balloons into a blob at deep zoom', () {
      expect(
        PdfAndroidSelectionControls.sizeFor(charHeightOnScreen: 500, dragging: false),
        48,
      );
    });

    test('grows while dragged', () {
      final still = PdfAndroidSelectionControls.sizeFor(
          charHeightOnScreen: 20, dragging: false);
      final dragging = PdfAndroidSelectionControls.sizeFor(
          charHeightOnScreen: 20, dragging: true);
      expect(dragging, closeTo(still * 1.2, 0.01));
    });
  });

  group('buildHandle', () {
    Future<double> pumpAndReadScale(
      WidgetTester tester, {
      required PdfTextSelectionAnchorType type,
      required double zoom,
      PdfViewerTextSelectionAnchorHandleState state =
          PdfViewerTextSelectionAnchorHandleState.normal,
    }) async {
      final controls = PdfAndroidSelectionControls(zoomOf: () => zoom);
      await tester.pumpWidget(
        MaterialApp(
          home: PdfSelectionColorScope(
            child: Builder(
              builder: (context) => Center(
                child: controls.buildHandle(
                  context,
                  _anchor(type: type, direction: PdfTextDirection.ltr),
                  state,
                ),
              ),
            ),
          ),
        ),
      );

      // Transform.scale keeps the Z axis at 1, so getMaxScaleOnAxis() would
      // report 1.0 for any handle that shrinks below Material's 22dp; the X
      // axis is the one that actually carries the scale.
      final transform = tester.widget<Transform>(find.byType(Transform).first);
      return transform.transform.storage[0];
    }

    testWidgets('paints the Material teardrop in brand blue', (tester) async {
      await pumpAndReadScale(tester, type: PdfTextSelectionAnchorType.a, zoom: 1);

      final painter = tester
          .widget<CustomPaint>(
            find.descendant(
              of: find.byType(PdfSelectionColorScope),
              matching: find.byType(CustomPaint),
            ),
          )
          .painter;
      expect(
        painter.runtimeType.toString(),
        contains('TextSelectionHandlePainter'),
      );
      // The scoped theme, not the app's white/black ColorScheme, tints it.
      expect((painter! as dynamic).color, AppColors.primary);
    });

    testWidgets('scales with zoom instead of staying a fixed 22dp',
        (tester) async {
      // The 10pt test character: clamped up to 20 logical px at fit width,
      // 46 at 4x zoom.
      expect(
        await pumpAndReadScale(tester,
            type: PdfTextSelectionAnchorType.a, zoom: 1),
        closeTo(20 / kMaterialSelectionHandleSize, 0.01),
      );
      expect(
        await pumpAndReadScale(tester,
            type: PdfTextSelectionAnchorType.a, zoom: 1),
        lessThan(1.0),
        reason: 'A fit-width page renders text smaller than Material\'s fixed '
            '22dp glyph, so the handle must shrink with it.',
      );
      expect(
        await pumpAndReadScale(tester,
            type: PdfTextSelectionAnchorType.a, zoom: 4),
        closeTo(46 / kMaterialSelectionHandleSize, 0.01),
      );
    });

    testWidgets('swells while dragging', (tester) async {
      final still = await pumpAndReadScale(tester,
          type: PdfTextSelectionAnchorType.a, zoom: 4);
      final dragging = await pumpAndReadScale(
        tester,
        type: PdfTextSelectionAnchorType.a,
        zoom: 4,
        state: PdfViewerTextSelectionAnchorHandleState.dragging,
      );
      expect(dragging, closeTo(still * 1.2, 0.02));
    });
  });
}
