/*
 * File: document_viewer_screen.dart
 * Description: Unified document viewer screen supporting PDF documents, text/code files with editing, and Office fallback cards.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/document_viewer_cache_service.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/core/theme/app_colors_extension.dart';
import 'package:telstorage/shared/widgets/thumbnail_widget.dart';
import 'viewmodel/document_viewer_viewmodel.dart';
import 'widgets/document_top_bar.dart';
import 'widgets/office_fallback_card.dart';
import 'widgets/pdf_viewer_adapter.dart';
import 'widgets/text_editor_adapter.dart';

/// Fixed size of the centered saving-progress overlay card (width x height).
const double _kSavingProgressCardWidth = 260;
const double _kSavingProgressCardHeight = 170;

/// Fixed height of the full-width loading progress card (width = full width).
const double _kLoadingProgressCardHeight = 100;

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
  String? _lastShownError;
  final GlobalKey<PdfViewerAdapterState> _pdfViewerKey =
      GlobalKey<PdfViewerAdapterState>();

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _viewModel = widget.viewModel ?? DocumentViewerViewModel(file: widget.file);
    _viewModel.addListener(_onStateChanged);
    if (widget.viewModel == null) {
      _viewModel.init();
    }
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
    _showSaveErrorIfNeeded();
  }

  /// Surfaces save failures (which keep the document on screen) as a SnackBar.
  /// Initial load errors still use the inline full-screen error state.
  void _showSaveErrorIfNeeded() {
    final error = _viewModel.errorMessage;
    if (error == null) {
      _lastShownError = null;
      return;
    }
    if (_viewModel.localFile == null || error == _lastShownError) return;
    _lastShownError = error;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(error),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _viewModel.removeListener(_onStateChanged);
    if (widget.viewModel == null) {
      _viewModel.dispose();
    }
    super.dispose();
  }

  Future<bool> _handleWillPop() async {
    // Never allow the screen to close while a save is committing.
    if (_viewModel.isSaving) return false;
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

  Widget _buildLoadingState(AppColorsExtension? colors) {
    final file = widget.file;
    final progress = _viewModel.progress;
    final hasProgress = progress > 0;
    final percentText = (progress * 100).clamp(0, 100).toInt();

    final totalMb = file.sizeMb;
    final downloadedMb = totalMb * progress;
    final progressDetail = totalMb > 0
        ? '${downloadedMb.toStringAsFixed(1)} MB / ${totalMb.toStringAsFixed(1)} MB'
        : null;

    final displayStatus = _viewModel.statusMessage == 'Reading file index…'
        ? 'Preparing document…'
        : _viewModel.statusMessage;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            // Thumbnail Card Preview
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withValues(alpha: 0.28),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ThumbnailWidget(
                  file: file,
                  width: 140,
                  height: 190,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 20),
            // File Name
            Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors?.textPrimary ?? AppColors.white,
              ),
            ),
            const SizedBox(height: 6),
            // File Size Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: colors?.bgSurfaceInset ?? AppColors.grey800,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                file.formattedSize,
                style: TextStyle(
                  fontSize: 12,
                  color: colors?.textSecondary ?? AppColors.grey600,
                ),
              ),
            ),
            const Spacer(),
            // Bottom Progress Card: fixed height, never grows with its text.
            Container(
              key: const Key('loadingProgressCard'),
              width: double.infinity,
              height: _kLoadingProgressCardHeight,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors?.bgSurface ?? AppColors.grey900,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors?.borderSubtle ?? AppColors.grey800,
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: hasProgress ? progress : null,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colors?.accentPrimary ?? AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          displayStatus,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colors?.textPrimary ?? AppColors.white,
                          ),
                        ),
                      ),
                      if (hasProgress)
                        Text(
                          '$percentText%',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors?.accentPrimary ?? AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: hasProgress ? progress : null,
                      minHeight: 6,
                      backgroundColor: colors?.bgSurfaceInset ?? AppColors.grey800,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colors?.accentPrimary ?? AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Slot is always reserved so the card height never changes.
                  SizedBox(
                    height: 16,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        progressDetail ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors?.textSecondary ?? AppColors.grey600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final colors = Theme.of(context).extension<AppColorsExtension>();

    if (_viewModel.isLoading && _viewModel.localFile == null) {
      return _buildLoadingState(colors);
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
        key: _pdfViewerKey,
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

  Widget _buildSavingOverlay(AppColorsExtension? colors) {
    final progress = _viewModel.progress;
    final hasProgress = progress > 0;
    final percent = (progress * 100).clamp(0, 100).toInt();

    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: AppColors.black.withValues(alpha: 0.55),
          child: Center(
            child: Container(
              key: const Key('savingProgressCard'),
              width: _kSavingProgressCardWidth,
              height: _kSavingProgressCardHeight,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colors?.bgSurface ?? AppColors.grey900,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      value: hasProgress ? progress : null,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Fixed-height slots keep the card size independent of text.
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: Center(
                      child: Text(
                        _viewModel.statusMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors?.textPrimary ?? AppColors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 18,
                    child: Center(
                      child: Text(
                        hasProgress ? '$percent%' : '',
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors?.textSecondary ?? AppColors.grey600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();

    return PopScope(
      canPop: !_viewModel.isDirty && !_viewModel.isSaving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _handleWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: colors?.bgPrimary ?? AppColors.black,
        body: Stack(
          children: [
            Column(
              children: [
                // Auto-hiding top bar: it occupies real layout space and collapses
                // to zero height when chrome is hidden, so the document slides up to
                // the screen edge instead of being overlaid by a floating bar.
                ClipRect(
                  child: AnimatedAlign(
                    alignment: Alignment.topCenter,
                    heightFactor: _viewModel.isChromeVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    child: DocumentTopBar(
                      viewModel: _viewModel,
                      onBack: () async {
                        if (await _handleWillPop() && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      onToggleSearch: () =>
                          setState(() => _isSearchOpen = !_isSearchOpen),
                      onOpenOutline: () =>
                          _pdfViewerKey.currentState?.showOutline(),
                    ),
                  ),
                ),
                Expanded(child: _buildContent()),
              ],
            ),
            if (_viewModel.isSaving) _buildSavingOverlay(colors),
          ],
        ),
      ),
    );
  }
}
