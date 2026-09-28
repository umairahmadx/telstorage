/*
 * File: pdf_viewer_adapter.dart
 * Description: PDF rendering adapter using pdfrx with text search, reading themes, pinch-zoom, and page scrubber synchronization.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import '../viewmodel/document_viewer_viewmodel.dart';
import 'document_page_scrubber.dart';
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

  void _onSearchUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _textSearcher?.removeListener(_onSearchUpdated);
    _textSearcher?.dispose();
    super.dispose();
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
        GestureDetector(
          onTap: () => widget.viewModel.toggleChrome(),
          child: _applyThemeFilter(
            PdfViewer.file(
              widget.file.path,
              controller: _controller,
              params: PdfViewerParams(
                pagePaintCallbacks: [
                  if (_textSearcher != null) _textSearcher!.pageTextMatchPaintCallback,
                ],
                onViewerReady: (doc, controller) {
                  _textSearcher ??= PdfTextSearcher(_controller)
                    ..addListener(_onSearchUpdated);
                  widget.viewModel.setPage(1, total: doc.pages.length);
                  if (mounted) setState(() {});
                },
                onPageChanged: (page) {
                  if (page != null) widget.viewModel.setPage(page);
                },
              ),
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
        if (widget.viewModel.isChromeVisible)
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: DocumentPageScrubber(
              viewModel: widget.viewModel,
              onPageSelected: (page) => _controller.goToPage(pageNumber: page),
            ),
          ),
      ],
    );
  }
}
