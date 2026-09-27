/*
 * File: device_file_filter_tabs.dart
 * Description: Category filter tabs for filtering device files by type (All, Documents, Audio, Archives).
 */

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../../core/theme/app_colors_extension.dart';

/// Horizontal category filter tab bar for narrowing device files by extension family.
class DeviceFileFilterTabs extends StatelessWidget {
  /// Currently active category filter label.
  final String activeFilter;

  /// Callback when a filter tab is selected.
  final ValueChanged<String> onFilterChanged;

  /// Available filter categories.
  static const List<String> categories = [
    'All',
    'Documents',
    'Audio',
    'Archives',
  ];

  /// Constructs DeviceFileFilterTabs.
  const DeviceFileFilterTabs({
    super.key,
    required this.activeFilter,
    required this.onFilterChanged,
  });

  /// Evaluates whether a filename matches the specified category filter.
  static bool matchesFilter(String filename, String filter) {
    if (filter == 'All') return true;
    final ext = p.extension(filename).toLowerCase();

    switch (filter) {
      case 'Documents':
        return const {
          '.pdf',
          '.docx',
          '.xlsx',
          '.txt',
          '.pptx',
          '.doc',
          '.xls',
          '.csv',
          '.md',
          '.epub',
        }.contains(ext);
      case 'Audio':
        return const {
          '.mp3',
          '.m4a',
          '.flac',
          '.wav',
          '.ogg',
          '.aac',
          '.opus',
          '.wma',
        }.contains(ext);
      case 'Archives':
        return const {
          '.zip',
          '.rar',
          '.7z',
          '.tar',
          '.gz',
          '.001',
          '.bz2',
          '.xz',
          '.iso',
        }.contains(ext);
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = cat == activeFilter;

          return Material(
            color: isSelected
                ? (colors?.accentPrimary ?? Colors.blue)
                : (colors?.bgSurfaceInset ?? Colors.white10),
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => onFilterChanged(cat),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Center(
                  child: Text(
                    cat,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (colors?.textSecondary ?? Colors.white70),
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
