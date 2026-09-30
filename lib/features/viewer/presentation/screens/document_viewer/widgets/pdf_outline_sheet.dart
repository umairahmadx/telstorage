/*
 * File: pdf_outline_sheet.dart
 * Description: Bottom sheet listing a PDF document's outline (table of
 * contents) and reporting the destination of the entry the user taps.
 */

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/core/theme/app_colors_extension.dart';

/// Bottom sheet listing the PDF outline (table of contents).
class PdfOutlineSheet extends StatelessWidget {
  /// Creates the outline sheet for the flattened [nodes] tree.
  const PdfOutlineSheet({
    super.key,
    required this.nodes,
    required this.onSelect,
  });

  /// Outline tree to flatten into an indented list.
  final List<PdfOutlineNode> nodes;

  /// Called with the destination of the tapped entry, after the sheet closes.
  final void Function(PdfDest? dest) onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();

    final entries = <_OutlineEntry>[];
    void flatten(List<PdfOutlineNode> list, int depth) {
      for (final node in list) {
        entries.add(_OutlineEntry(node, depth));
        flatten(node.children, depth + 1);
      }
    }

    flatten(nodes, 0);

    return Container(
      decoration: BoxDecoration(
        color: colors?.bgSurface ?? AppColors.grey900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: (colors?.borderSubtle ?? AppColors.grey800)
                    .withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Contents',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: colors?.textPrimary ?? AppColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: EdgeInsets.only(
                      left: 20 + entry.depth * 18.0,
                      right: 20,
                    ),
                    title: Text(
                      entry.node.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: entry.depth == 0
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: colors?.textPrimary ?? AppColors.white,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelect(entry.node.dest);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One flattened outline row: a [node] and how deep it sits in the tree.
class _OutlineEntry {
  const _OutlineEntry(this.node, this.depth);

  final PdfOutlineNode node;
  final int depth;
}
