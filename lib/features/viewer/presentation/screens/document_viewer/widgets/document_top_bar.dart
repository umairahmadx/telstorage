/*
 * File: document_top_bar.dart
 * Description: Top navigation bar for the document viewer displaying file title, size, search, theme, edit toggle, and overflow actions.
 */

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:telstorage/core/services/document_viewer_cache_service.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/core/theme/app_colors_extension.dart';
import '../viewmodel/document_viewer_viewmodel.dart';

/// Top App Bar for DocumentViewerScreen.
class DocumentTopBar extends StatelessWidget implements PreferredSizeWidget {
  /// Active ViewModel.
  final DocumentViewerViewModel viewModel;

  /// Callback when user taps back button.
  final VoidCallback onBack;

  /// Callback when user taps search button.
  final VoidCallback onToggleSearch;

  /// Callback when user opens theme picker sheet.
  final VoidCallback? onOpenThemeSheet;

  /// Constructs DocumentTopBar.
  const DocumentTopBar({
    super.key,
    required this.viewModel,
    required this.onBack,
    required this.onToggleSearch,
    this.onOpenThemeSheet,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();
    final isPdf = DocumentViewerCacheService.isPdfRecord(viewModel.currentFile);
    final isText = DocumentViewerCacheService.isTextRecord(viewModel.currentFile);

    return Container(
      color: (colors?.bgSurface ?? AppColors.grey900).withValues(alpha: 0.92),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                color: colors?.textPrimary ?? AppColors.white,
                tooltip: 'Back',
                onPressed: onBack,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      viewModel.currentFile.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors?.textPrimary ?? AppColors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    Row(
                      children: [
                        Text(
                          viewModel.currentFile.formattedSize,
                          style: TextStyle(
                            fontSize: 11,
                            color: colors?.textSecondary ?? AppColors.grey600,
                          ),
                        ),
                        if (viewModel.isEditMode) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Editing',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search),
                color: colors?.textPrimary ?? AppColors.white,
                tooltip: 'Search',
                onPressed: onToggleSearch,
              ),
              if (isPdf && onOpenThemeSheet != null)
                IconButton(
                  icon: const Icon(Icons.palette_outlined),
                  color: colors?.textPrimary ?? AppColors.white,
                  tooltip: 'Reading theme',
                  onPressed: onOpenThemeSheet,
                ),
              if (isText)
                IconButton(
                  icon: Icon(
                    viewModel.isEditMode ? Icons.check : Icons.edit_outlined,
                  ),
                  color: viewModel.isEditMode
                      ? AppColors.success
                      : (colors?.textPrimary ?? AppColors.white),
                  tooltip: viewModel.isEditMode ? 'Done editing' : 'Edit file',
                  onPressed: () {
                    if (viewModel.isEditMode && viewModel.isDirty) {
                      viewModel.saveChanges();
                    } else {
                      viewModel.toggleEditMode();
                    }
                  },
                ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                color: colors?.textPrimary ?? AppColors.white,
                tooltip: 'Share',
                onPressed: () {
                  final path = viewModel.localFile?.path;
                  if (path != null) {
                    SharePlus.instance.share(
                      ShareParams(
                        files: [XFile(path)],
                        text: viewModel.currentFile.name,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
