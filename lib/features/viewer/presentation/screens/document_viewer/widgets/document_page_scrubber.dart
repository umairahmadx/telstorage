/*
 * File: document_page_scrubber.dart
 * Description: Bottom translucent floating HUD pill displaying page numbers with jump-to-page dialog and scrubber slider.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/core/theme/app_colors_extension.dart';
import '../viewmodel/document_viewer_viewmodel.dart';

/// Bottom HUD pill with page count and slider.
class DocumentPageScrubber extends StatelessWidget {
  /// Active ViewModel.
  final DocumentViewerViewModel viewModel;

  /// Callback when user selects a target page.
  final ValueChanged<int> onPageSelected;

  /// Constructs DocumentPageScrubber.
  const DocumentPageScrubber({
    super.key,
    required this.viewModel,
    required this.onPageSelected,
  });

  void _showJumpDialog(BuildContext context) {
    final controller =
        TextEditingController(text: '${viewModel.currentPage}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jump to Page'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Page (1 - ${viewModel.pageCount})',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final page = int.tryParse(controller.text);
              if (page != null && page >= 1 && page <= viewModel.pageCount) {
                onPageSelected(page);
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();
    final total = viewModel.pageCount > 0 ? viewModel.pageCount : 1;
    final current = viewModel.currentPage.clamp(1, total);

    return Material(
      color: Colors.transparent,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: (colors?.bgSurface ?? AppColors.grey900)
              .withValues(alpha: 0.90),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: (colors?.borderSubtle ?? AppColors.grey800)
                .withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showJumpDialog(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Page $current of $total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: colors?.textPrimary ?? AppColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.grey700,
                  thumbColor: AppColors.primary,
                ),
                child: Slider(
                  value: current.toDouble(),
                  min: 1.0,
                  max: total.toDouble(),
                  divisions: total > 1 ? total - 1 : 1,
                  onChanged: (val) => onPageSelected(val.round()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
