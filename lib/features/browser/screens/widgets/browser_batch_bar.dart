import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class BrowserBatchBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onClearSelection;
  final VoidCallback onDelete;
  final VoidCallback onMove;
  final VoidCallback onCopy;

  const BrowserBatchBar({
    super.key,
    required this.selectedCount,
    required this.onClearSelection,
    required this.onDelete,
    required this.onMove,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        boxShadow: [
          BoxShadow(
            color: colors.textPrimary.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: onClearSelection,
            ),
            Text(
              '$selectedCount selected',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.content_copy_rounded),
              tooltip: 'Copy',
              onPressed: onCopy,
            ),
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              tooltip: 'Move',
              onPressed: onMove,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: colors.error),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
