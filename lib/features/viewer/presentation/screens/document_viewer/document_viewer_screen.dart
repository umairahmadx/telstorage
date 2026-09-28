/*
 * File: document_viewer_screen.dart
 * Description: Unified document viewer screen supporting PDF documents, text/code files with editing, and Office fallback cards.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/document_viewer_cache_service.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/core/theme/app_colors_extension.dart';
import 'viewmodel/document_viewer_viewmodel.dart';
import 'widgets/document_top_bar.dart';
import 'widgets/office_fallback_card.dart';
import 'widgets/pdf_viewer_adapter.dart';
import 'widgets/reading_theme_sheet.dart';
import 'widgets/text_editor_adapter.dart';

/// Fullscreen document viewing and editing screen.
class DocumentViewerScreen extends StatefulWidget {
  /// File to view.
  final FileRecord file;

  /// Optional pre-injected ViewModel for testing.
  final DocumentViewerViewModel? viewModel;

  /// Constructs DocumentViewerScreen.
  const DocumentViewerScreen({
    super.key,
    required this.file,
    this.viewModel,
  });

  /// Opens DocumentViewerScreen with a smooth fade route transition.
  static void open(
    BuildContext context, {
    required FileRecord file,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, anim1, anim2) => FadeTransition(
          opacity: anim1,
          child: DocumentViewerScreen(file: file),
        ),
      ),
    );
  }

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  late final DocumentViewerViewModel _viewModel;
  bool _isSearchOpen = false;

  @override
  void initState() {
    super.initState();
    _viewModel = widget.viewModel ?? DocumentViewerViewModel(file: widget.file);
    _viewModel.addListener(_onStateChanged);
    if (widget.viewModel == null) {
      _viewModel.init();
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChanged);
    if (widget.viewModel == null) {
      _viewModel.dispose();
    }
    super.dispose();
  }

  Future<bool> _handleWillPop() async {
    if (_viewModel.isDirty) {
      final shouldDiscard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
            'You have unsaved changes that will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep Editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      return shouldDiscard ?? false;
    }
    return true;
  }

  void _showReadingThemeSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ReadingThemeSheet(
        currentTheme: _viewModel.readingTheme,
        onThemeChanged: (theme) => _viewModel.setReadingTheme(theme),
      ),
    );
  }

  Widget _buildContent() {
    final colors = Theme.of(context).extension<AppColorsExtension>();

    if (_viewModel.isLoading && _viewModel.localFile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _viewModel.statusMessage,
              style: TextStyle(
                color: colors?.textSecondary ?? AppColors.grey600,
              ),
            ),
          ],
        ),
      );
    }

    if (_viewModel.errorMessage != null && _viewModel.localFile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _viewModel.errorMessage!,
              style: TextStyle(
                color: colors?.textPrimary ?? AppColors.white,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _viewModel.init(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (DocumentViewerCacheService.isPdfRecord(_viewModel.currentFile)) {
      return PdfViewerAdapter(
        viewModel: _viewModel,
        file: _viewModel.localFile!,
        isSearchOpen: _isSearchOpen,
        onCloseSearch: () => setState(() => _isSearchOpen = false),
      );
    }

    if (DocumentViewerCacheService.isTextRecord(_viewModel.currentFile)) {
      return TextEditorAdapter(viewModel: _viewModel);
    }

    return OfficeFallbackCard(
      file: _viewModel.currentFile,
      localFile: _viewModel.localFile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();

    return PopScope(
      canPop: !_viewModel.isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _handleWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: colors?.bgPrimary ?? AppColors.black,
        appBar: _viewModel.isChromeVisible
            ? DocumentTopBar(
                viewModel: _viewModel,
                onBack: () async {
                  if (await _handleWillPop() && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                onToggleSearch: () =>
                    setState(() => _isSearchOpen = !_isSearchOpen),
                onOpenThemeSheet: _showReadingThemeSheet,
              )
            : null,
        body: _buildContent(),
      ),
    );
  }
}
