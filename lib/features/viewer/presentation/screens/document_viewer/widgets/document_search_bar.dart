/*
 * File: document_search_bar.dart
 * Description: Floating search bar overlay with debounced input, match count badge, and navigation chevrons.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/core/theme/app_colors_extension.dart';

/// Floating search bar for document text search.
class DocumentSearchBar extends StatefulWidget {
  /// Current match index (1-based).
  final int currentMatchIndex;

  /// Total number of matches found.
  final int totalMatches;

  /// Callback when query changes.
  final ValueChanged<String> onQueryChanged;

  /// Callback to jump to previous match.
  final VoidCallback onPreviousMatch;

  /// Callback to jump to next match.
  final VoidCallback onNextMatch;

  /// Callback to dismiss search bar.
  final VoidCallback onClose;

  /// Constructs DocumentSearchBar.
  const DocumentSearchBar({
    super.key,
    required this.currentMatchIndex,
    required this.totalMatches,
    required this.onQueryChanged,
    required this.onPreviousMatch,
    required this.onNextMatch,
    required this.onClose,
  });

  @override
  State<DocumentSearchBar> createState() => _DocumentSearchBarState();
}

class _DocumentSearchBarState extends State<DocumentSearchBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();

    return Card(
      elevation: 6,
      color: colors?.bgSurface ?? AppColors.grey800,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.search, size: 20, color: AppColors.grey600),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                style: TextStyle(
                  fontSize: 14,
                  color: colors?.textPrimary ?? AppColors.white,
                ),
                decoration: const InputDecoration(
                  hintText: 'Find in document…',
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: widget.onQueryChanged,
              ),
            ),
            if (widget.totalMatches > 0) ...[
              Text(
                '${widget.currentMatchIndex} of ${widget.totalMatches}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.grey600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                onPressed: widget.onPreviousMatch,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                onPressed: widget.onNextMatch,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: widget.onClose,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
