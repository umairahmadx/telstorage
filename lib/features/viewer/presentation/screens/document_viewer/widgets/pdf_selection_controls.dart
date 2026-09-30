/*
 * File: pdf_selection_controls.dart
 * Description: Android-style text selection visuals for the pdfrx PDF viewer:
 * a brand-blue highlight plus the platform teardrop handles, scaled to the
 * text they point at.
 */

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:telstorage/core/theme/app_colors.dart';

/// Width and height of Flutter's Material selection handle glyph.
///
/// `MaterialTextSelectionControls` always paints a fixed 22x22 teardrop and
/// declares where its tip sits through `getHandleAnchor`: the top-right corner
/// of that box for [TextSelectionHandleType.left] and the top-left corner for
/// [TextSelectionHandleType.right]. Both facts drive the placement maths in
/// [PdfAndroidSelectionControls].
const double kMaterialSelectionHandleSize = 22;

/// Scopes the brand selection colors to the PDF viewer subtree.
///
/// `PdfTextSelectionParams` has no color fields of its own: pdfrx reads the
/// highlight wash from `TextSelectionTheme.of(context)`, falling back to a grey
/// tint derived from `ColorScheme.primary` (white/black in this app's themes,
/// which is why the default selection reads as washed out grey). The Material
/// handle glyph reads `selectionHandleColor` from the same theme, so wrapping
/// the viewer is the narrowest hook available to tint PDF selection blue.
/// Dialogs and bottom sheets opened from the viewer live in the Navigator's
/// overlay above this subtree and therefore keep the app-wide theme.
class PdfSelectionColorScope extends StatelessWidget {
  /// Wraps [child] — the PDF viewer — in the brand selection theme.
  const PdfSelectionColorScope({super.key, required this.child});

  /// Subtree whose selection should render in brand blue.
  final Widget child;

  /// Handle tint, matching the teardrops Android draws for this app's fields.
  static Color get handleColor => AppColors.primary;

  /// Highlight tint: brand blue, translucent enough to keep glyphs legible.
  static Color get highlightColor =>
      AppColors.primary.withValues(alpha: 0.35);

  @override
  Widget build(BuildContext context) {
    return TextSelectionTheme(
      data: TextSelectionThemeData(
        selectionHandleColor: handleColor,
        selectionColor: highlightColor,
      ),
      child: child,
    );
  }
}

/// Builds the PDF text selection handles as Android's teardrops.
///
/// pdfrx defaults to right-angled grey triangles. The two hooks it exposes on
/// `PdfTextSelectionParams` — `buildSelectionHandle` and
/// `calcSelectionHandleOffset` — are enough to swap them for
/// `MaterialTextSelectionControls`' glyph, the same asset pair the platform
/// renders for the app's own text fields on Android.
class PdfAndroidSelectionControls {
  /// [zoomOf] must report the viewer's current zoom. pdfrx hands the anchored
  /// character rectangle over in *document* coordinates, so the on-screen text
  /// height — what the handle has to be sized against — is unknowable without
  /// it.
  PdfAndroidSelectionControls({required this.zoomOf});

  /// Current zoom level of the hosting viewer.
  final double Function() zoomOf;

  static final MaterialTextSelectionControls _materialControls =
      MaterialTextSelectionControls();

  /// Android enlarges a handle while it is being dragged; same nudge here.
  static const double _draggingGrowth = 1.2;

  /// Android keeps the teardrop slightly taller than the text it points at.
  static const double _handleToTextRatio = 1.15;
  static const double _minHandleSize = 20;
  static const double _maxHandleSize = 48;

  /// Hook for `PdfTextSelectionParams.buildSelectionHandle`.
  Widget? buildHandle(
    BuildContext context,
    PdfTextSelectionAnchor anchor,
    PdfViewerTextSelectionAnchorHandleState state,
  ) {
    final handleType = handleTypeFor(
      type: anchor.type,
      direction: anchor.direction,
    );
    final lineHeight = anchor.rect.height * zoomOf();
    final size = sizeFor(
      charHeightOnScreen: lineHeight,
      dragging: state == PdfViewerTextSelectionAnchorHandleState.dragging,
    );

    return Transform.scale(
      // Scaling about the tip corner keeps the teardrop pointing at exactly the
      // anchored character corner as it grows; scaling about the centre, which
      // is what Transform does by default, would slide the tip off the text.
      scale: size / kMaterialSelectionHandleSize,
      alignment: tipAlignment(handleType),
      child: _materialControls.buildHandle(context, handleType, lineHeight),
    );
  }

  /// Hook for `PdfTextSelectionParams.calcSelectionHandleOffset`.
  Offset calcHandleOffset(
    BuildContext context,
    PdfTextSelectionAnchor anchor,
    PdfViewerTextSelectionAnchorHandleState state,
  ) =>
      offsetFor(anchor.type);

  /// Picks the glyph whose tip lands on the corner pdfrx anchors [type] to.
  ///
  /// pdfrx anchors A on `rect.topLeft` and B on `rect.bottomRight` for
  /// left-to-right text, and swaps both corners for right-to-left and vertical
  /// runs (it swaps which box edge it pins, too), so the glyph pair has to
  /// mirror with them. Android ships no vertical variant of the teardrop, so
  /// vertical runs reuse the mirrored pair: the tip still touches the anchor, it
  /// just enters from the side.
  @visibleForTesting
  static TextSelectionHandleType handleTypeFor({
    required PdfTextSelectionAnchorType type,
    required PdfTextDirection direction,
  }) {
    final mirrored =
        direction == PdfTextDirection.rtl || direction == PdfTextDirection.vrtl;
    if (type == PdfTextSelectionAnchorType.a) {
      return mirrored
          ? TextSelectionHandleType.right
          : TextSelectionHandleType.left;
    }
    return mirrored
        ? TextSelectionHandleType.left
        : TextSelectionHandleType.right;
  }

  /// Shift pdfrx must apply to a handle box so its tip reaches the anchor.
  ///
  /// pdfrx pins handle A's box by its *bottom* edge onto the anchored corner
  /// (`bottom: viewHeight - rect.top - offset.dy`) while the Material glyph
  /// carries its tip on the box's *top* edge, so A has to be pushed down by
  /// exactly one box height. Handle B is pinned by its top edge, which is
  /// already where its tip sits, so it needs no shift.
  @visibleForTesting
  static Offset offsetFor(PdfTextSelectionAnchorType type) =>
      type == PdfTextSelectionAnchorType.a
          ? const Offset(0, kMaterialSelectionHandleSize)
          : Offset.zero;

  /// Corner of the handle box that carries the glyph's tip.
  @visibleForTesting
  static Alignment tipAlignment(TextSelectionHandleType type) =>
      type == TextSelectionHandleType.left
          ? Alignment.topRight
          : Alignment.topLeft;

  /// Handle box size suited to a character [charHeightOnScreen] tall.
  ///
  /// Clamped both ways: the teardrop stays readable at deep zoom without
  /// turning into a blob, and never shrinks below a target a finger can find at
  /// fit-width zoom.
  @visibleForTesting
  static double sizeFor({
    required double charHeightOnScreen,
    required bool dragging,
  }) {
    final base = (charHeightOnScreen * _handleToTextRatio)
        .clamp(_minHandleSize, _maxHandleSize)
        .toDouble();
    return dragging ? base * _draggingGrowth : base;
  }
}
