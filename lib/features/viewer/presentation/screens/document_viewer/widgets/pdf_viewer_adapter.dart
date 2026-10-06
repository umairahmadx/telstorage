/*
 * File: pdf_viewer_adapter.dart
 * Description: PDF rendering adapter using pdfrx with text search, pinch-zoom, and floating page thumb.
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import '../viewmodel/document_viewer_viewmodel.dart';
import 'document_search_bar.dart';
import 'pdf_outline_sheet.dart';
import 'pdf_selection_controls.dart';

/// PDF viewer adapter widget.
class PdfViewerAdapter extends StatefulWidget {
  /// Active ViewModel.
  final DocumentViewerViewModel viewModel;

  /// Local PDF file.
  final File file;

  /// Whether search bar is open.
  final bool isSearchOpen;

  /// Callback when user closes search.
  final VoidCallback? onCloseSearch;

  /// Constructs PdfViewerAdapter.
  const PdfViewerAdapter({
    super.key,
    required this.viewModel,
    required this.file,
    this.isSearchOpen = false,
    this.onCloseSearch,
  });

  @override
  State<PdfViewerAdapter> createState() => PdfViewerAdapterState();
}
class PdfViewerAdapterState extends State<PdfViewerAdapter> {
  final PdfViewerController _controller = PdfViewerController();

  /// Android-style teardrop handles, sized against the text they point at.
  late final PdfAndroidSelectionControls _selectionControls =
      PdfAndroidSelectionControls(zoomOf: () => _controller.currentZoom);
  PdfTextSearcher? _textSearcher;
  Timer? _hideScrollThumbTimer;
  bool _isScrollThumbVisible = true;

  /// Loaded PDF document (for outline access).
  PdfDocument? _document;

  /// Restored reading position (page + zoom) from local storage.
  int? _restoredPage;
  double? _restoredZoom;

  /// Tracked current position for persistence.
  int? _lastPage;
  double? _lastZoom;
  Timer? _savePositionTimer;

  static const _scrollThumbHideDelay = Duration(seconds: 2);
  static const double _chromeScrollThreshold = 6.0;

  void _onSearchUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideScrollThumbTimer?.cancel();
    _savePositionTimer?.cancel();
    _savePosition(); // persist final position (tracked values, no controller access)
    _textSearcher?.removeListener(_onSearchUpdated);
    _textSearcher?.dispose();
    super.dispose();
  }

  void _showScrollThumb() {
    _hideScrollThumbTimer?.cancel();
    if (!_isScrollThumbVisible && mounted) {
      setState(() => _isScrollThumbVisible = true);
    }
    _hideScrollThumbTimer = Timer(_scrollThumbHideDelay, () {
      if (mounted) setState(() => _isScrollThumbVisible = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  String get _positionPageKey =>
      'pdf_position_${widget.viewModel.currentFile.fileId}_page';
  String get _positionZoomKey =>
      'pdf_position_${widget.viewModel.currentFile.fileId}_zoom';

  Future<void> _loadPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final page = prefs.getInt(_positionPageKey);
    final zoom = prefs.getDouble(_positionZoomKey);
    if (mounted && page != null && page > 0) {
      _restoredPage = page;
      _restoredZoom = zoom;
    }
  }

  Future<void> _savePosition() async {
    final page = _lastPage;
    if (page == null || page < 1) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_positionPageKey, page);
    final zoom = _lastZoom;
    if (zoom != null && zoom > 0) {
      await prefs.setDouble(_positionZoomKey, zoom);
    }
  }

  void _scheduleSavePosition() {
    _savePositionTimer?.cancel();
    _savePositionTimer =
        Timer(const Duration(milliseconds: 400), _savePosition);
  }

  void _restorePosition(PdfViewerController controller, PdfDocument doc) {
    final page = _restoredPage;
    if (page == null || page < 1 || page > doc.pages.length) {
      _centerShortDocument(controller.viewSize, controller);
      return;
    }
    final zoom = _restoredZoom ??
        controller.alternativeFitScale ??
        controller.coverScale;
    final pageRect = controller.layout.pageLayouts[page - 1];
    controller.goTo(
      controller.calcMatrixFor(pageRect.center, zoom: zoom),
      duration: Duration.zero,
    );
  }

  /// Opens the outline/table-of-contents bottom sheet.
  Future<void> showOutline() async {
    final document = _document;
    if (document == null) return;
    final nodes = await document.loadOutline();
    if (!mounted) return;
    if (nodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No table of contents in this document'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => PdfOutlineSheet(
        nodes: nodes,
        onSelect: (dest) {
          if (dest != null) {
            _controller.goToDest(dest);
            _scheduleSavePosition();
          }
        },
      ),
    );
  }

  /// Opens the "go to page" dialog.
  Future<void> showGoToPage() async {
    final total = _controller.pageCount;
    final current = _controller.pageNumber ?? 1;
    final textController = TextEditingController(text: '$current');

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: textController,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            hintText: '1 – $total',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(int.tryParse(value)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(ctx).pop(int.tryParse(textController.text)),
            child: const Text('Go'),
          ),
        ],
      ),
    );

    if (result == null) return;
    final page = result.clamp(1, total).toInt();
    if (page != _controller.pageNumber) {
      _controller.goToPage(pageNumber: page);
      _scheduleSavePosition();
    }
  }

  /// Zoom in one step (bottom bar).
  void zoomIn() {
    _controller.zoomUp(duration: const Duration(milliseconds: 160));
    _showScrollThumb();
  }

  /// Zoom out one step (bottom bar).
  void zoomOut() {
    _controller.zoomDown(duration: const Duration(milliseconds: 160));
    _showScrollThumb();
  }

  /// Direction-aware chrome hiding: scrolling down hides the bar (immersive
  /// reading), scrolling up reveals it. This avoids the "always hiding" feel
  /// of hiding on every interaction frame.
  void _onPdfScroll(ScaleUpdateDetails details) {
    _showScrollThumb();
    final dy = details.focalPointDelta.dy;
    if (dy > _chromeScrollThreshold) {
      widget.viewModel.setChromeVisible(true);
    } else if (dy < -_chromeScrollThreshold) {
      widget.viewModel.setChromeVisible(false);
    }
  }

  /// Handles single/double taps. Double tap always zooms (toggle fit ↔ 2× at
  /// the tap point); word selection is left to long-press (pdfrx's default).
  bool _onGeneralTap(
    BuildContext context,
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    if (details.type == PdfViewerGeneralTapType.doubleTap) {
      _handleDoubleTapZoom(controller, details);
      return true;
    }
    if (details.type == PdfViewerGeneralTapType.tap) {
      widget.viewModel.toggleChrome();
    }
    return false;
  }

  void _handleDoubleTapZoom(
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
  ) {
    final fitScale = controller.alternativeFitScale ?? controller.coverScale;
    final double targetZoom;
    if (controller.currentZoom >= fitScale * 1.5) {
      targetZoom = fitScale;
    } else {
      targetZoom = (fitScale * 2)
          .clamp(controller.minScale, controller.params.maxScale ?? double.infinity)
          .toDouble();
    }
    controller.setZoom(details.documentPosition, targetZoom);
    _showScrollThumb();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PdfSelectionColorScope(
          child: PdfViewer.file(
          widget.file.path,
          controller: _controller,
          params: PdfViewerParams(
              backgroundColor: AppColors.black,
              pageDropShadow: null,
              scrollPhysics: const ClampingScrollPhysics(),
              // The viewer itself clamps panning to its page boundaries. This
              // keeps a fit-width page from drifting sideways while still
              // allowing horizontal panning after the user zooms in.
              panAxis: PanAxis.free,
              pageAnchor: PdfPageAnchor.center,
              onInteractionStart: (_) => _showScrollThumb(),
              onInteractionUpdate: _onPdfScroll,
              onInteractionEnd: (_) {
                _showScrollThumb();
                _lastPage = _controller.pageNumber;
                _lastZoom = _controller.currentZoom;
                _scheduleSavePosition();
              },
              calculateInitialZoom:
                  (doc, controller, fitScale, coverScale) => fitScale,
              onGeneralTap: _onGeneralTap,
              textSelectionParams: PdfTextSelectionParams(
                showContextMenuAutomatically: true,
                // Swap pdfrx's grey triangles for Android's blue teardrops.
                buildSelectionHandle: _selectionControls.buildHandle,
                calcSelectionHandleOffset: _selectionControls.calcHandleOffset,
              ),
              pagePaintCallbacks: [
                if (_textSearcher != null)
                  _textSearcher!.pageTextMatchPaintCallback,
              ],
              viewerOverlayBuilder: (context, size, handleLinkTap) => [
                // NOTE: PdfViewerScrollThumb returns a `Positioned` from its build,
                // so it MUST be a direct child of the viewer's internal Stack. Do not
                // wrap it in render-object widgets (IgnorePointer/AnimatedOpacity)
                // here, or Positioned.applyParentData will cast a plain ParentData to
                // StackParentData and crash. Fade/ignore logic lives in thumbBuilder.
                PdfViewerScrollThumb(
                  controller: _controller,
                  orientation: ScrollbarOrientation.right,
                  thumbSize: const Size(64, 30),
                  margin: 14,
                  thumbBuilder: (context, thumbSize, pageNumber, controller) {
                    final page = pageNumber ?? 1;
                    final total = controller.pages.length;
                    return IgnorePointer(
                      ignoring: !_isScrollThumbVisible,
                      child: AnimatedOpacity(
                        opacity: _isScrollThumbVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: GestureDetector(
                          onTap: showGoToPage,
                          child: Container(
                            width: thumbSize.width,
                            height: thumbSize.height,
                          decoration: BoxDecoration(
                            color: AppColors.black.withValues(alpha: 0.76),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: AppColors.white.withValues(alpha: 0.20),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.black.withValues(alpha: 0.35),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$page/$total',
                            style: const TextStyle(
                              color: AppColors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
              onViewerReady: (doc, controller) {
                _document = doc;
                _textSearcher ??= PdfTextSearcher(_controller)
                  ..addListener(_onSearchUpdated);
                widget.viewModel.setPage(1, total: doc.pages.length);
                _showScrollThumb();
                _restorePosition(controller, doc);
                if (mounted) setState(() {});
              },
              onViewSizeChanged: (viewSize, oldViewSize, controller) =>
                  _centerShortDocument(viewSize, controller),
              onPageChanged: (page) {
                if (page != null) {
                  widget.viewModel.setPage(page);
                  _showScrollThumb();
                  _lastPage = page;
                  _scheduleSavePosition();
                }
              },
          ),
        ),
        ),
        if (widget.isSearchOpen)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: DocumentSearchBar(
              currentMatchIndex: _textSearcher?.currentIndex != null
                  ? _textSearcher!.currentIndex! + 1
                  : 0,
              totalMatches: _textSearcher?.matches.length ?? 0,
              onQueryChanged: (query) => _textSearcher?.startTextSearch(query),
              onPreviousMatch: () => _textSearcher?.goToPrevMatch(),
              onNextMatch: () => _textSearcher?.goToNextMatch(),
              onClose: () {
                _textSearcher?.resetTextSearch();
                widget.onCloseSearch?.call();
              },
            ),
          ),
      ],
    );
  }

  void _centerShortDocument(Size viewSize, PdfViewerController controller) {
    final docHeight = controller.documentSize.height * controller.currentZoom;
    if (docHeight >= viewSize.height || viewSize.height <= 0) return;

    final centerPos = Offset(
      controller.documentSize.width / 2,
      controller.documentSize.height / 2,
    );
    controller.goTo(
      controller.calcMatrixFor(centerPos),
      duration: Duration.zero,
    );
  }
}

