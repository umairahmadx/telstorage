/*
 * File: pdf_viewer_adapter.dart
 * Description: PDF rendering adapter using pdfrx with text search, reading themes, pinch-zoom, and floating page thumb.
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import '../viewmodel/document_viewer_viewmodel.dart';
import 'document_search_bar.dart';

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
  State<PdfViewerAdapter> createState() => _PdfViewerAdapterState();
}
class _PdfViewerAdapterState extends State<PdfViewerAdapter> {
  final PdfViewerController _controller = PdfViewerController();
  PdfTextSearcher? _textSearcher;
  Timer? _hideScrollThumbTimer;
  bool _isScrollThumbVisible = true;

  static const _scrollThumbHideDelay = Duration(seconds: 2);

  void _onSearchUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hideScrollThumbTimer?.cancel();
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

  void _onPdfInteraction() {
    widget.viewModel.setChromeVisible(false);
    _showScrollThumb();
  }

  Widget _applyThemeFilter(Widget child) {
    switch (widget.viewModel.readingTheme) {
      case DocumentReadingTheme.dark:
        return ColorFiltered(
          colorFilter: const ColorFilter.mode(
            AppColors.white,
            BlendMode.difference,
          ),
          child: child,
        );
      case DocumentReadingTheme.sepia:
        return ColorFiltered(
          colorFilter: const ColorFilter.mode(
            AppColors.sepiaPaper,
            BlendMode.multiply,
          ),
          child: child,
        );
      case DocumentReadingTheme.original:
        return child;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        _applyThemeFilter(
          PdfViewer.file(
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
              onInteractionStart: (_) => _onPdfInteraction(),
              onInteractionUpdate: (_) => _onPdfInteraction(),
              onInteractionEnd: (_) => _showScrollThumb(),
              calculateInitialZoom:
                  (doc, controller, fitScale, coverScale) => fitScale,
              pagePaintCallbacks: [
                if (_textSearcher != null)
                  _textSearcher!.pageTextMatchPaintCallback,
              ],
              viewerOverlayBuilder: (context, size, handleLinkTap) => [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    if (!handleLinkTap(details.localPosition)) {
                      widget.viewModel.toggleChrome();
                    }
                  },
                  child: IgnorePointer(
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: !_isScrollThumbVisible,
                  child: AnimatedOpacity(
                    opacity: _isScrollThumbVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    child: PdfViewerScrollThumb(
                      controller: _controller,
                      orientation: ScrollbarOrientation.right,
                      thumbSize: const Size(64, 30),
                      margin: 14,
                      thumbBuilder:
                          (context, thumbSize, pageNumber, controller) {
                        final page = pageNumber ?? 1;
                        final total = controller.pages.length;
                        return Container(
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
                        );
                      },
                    ),
                  ),
                ),
              ],
              onViewerReady: (doc, controller) {
                _textSearcher ??= PdfTextSearcher(_controller)
                  ..addListener(_onSearchUpdated);
                widget.viewModel.setPage(1, total: doc.pages.length);
                _showScrollThumb();
                _centerShortDocument(controller.viewSize, controller);
                if (mounted) setState(() {});
              },
              onViewSizeChanged: (viewSize, oldViewSize, controller) =>
                  _centerShortDocument(viewSize, controller),
              onPageChanged: (page) {
                if (page != null) {
                  widget.viewModel.setPage(page);
                  _showScrollThumb();
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

