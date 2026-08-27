/*
 * File: error_log_filter_bar.dart
 * Description: Filter and search bar header for narrowing diagnostic error logs by severity and keywords.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/models/error_log_record.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Header widget providing search query input and severity filtering controls.
class ErrorLogFilterBar extends StatelessWidget {
  /// Current active search keyword.
  final String searchQuery;

  /// Callback when search query updates.
  final ValueChanged<String> onSearchChanged;

  /// Current selected severity filter (`null` indicates all).
  final ErrorLogLevel? selectedLevel;

  /// Callback when a severity filter tab is selected.
  final ValueChanged<ErrorLogLevel?> onLevelSelected;

  /// Total count per category for badge indicators.
  final Map<ErrorLogLevel?, int> counts;

  /// Constructs ErrorLogFilterBar.
  const ErrorLogFilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.selectedLevel,
    required this.onLevelSelected,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Column(
      children: [
        // Search Input Field
        Container(
          decoration: BoxDecoration(
            color: colors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: TextField(
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search errors, tags, stack traces...',
              hintStyle:
                  TextStyle(color: colors.textTertiary, fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded,
                  color: colors.textSecondary, size: 20),
              suffixIcon: searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded,
                          color: colors.textSecondary, size: 18),
                      onPressed: () => onSearchChanged(''),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: onSearchChanged,
          ),
        ),
        const SizedBox(height: 12),

        // Filter Tabs
        Row(
          children: [
            _buildFilterChip(
              colors,
              label: 'All',
              level: null,
              count: counts[null] ?? 0,
              activeColor: colors.accentPrimary,
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              colors,
              label: 'Errors',
              level: ErrorLogLevel.error,
              count: counts[ErrorLogLevel.error] ?? 0,
              activeColor: colors.error,
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              colors,
              label: 'Warnings',
              level: ErrorLogLevel.warning,
              count: counts[ErrorLogLevel.warning] ?? 0,
              activeColor: colors.warning,
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              colors,
              label: 'Info',
              level: ErrorLogLevel.info,
              count: counts[ErrorLogLevel.info] ?? 0,
              activeColor: colors.accentPrimary,
            ),
          ],
        ),

      ],
    );
  }

  Widget _buildFilterChip(
    AppColorsExtension colors, {
    required String label,
    required ErrorLogLevel? level,
    required int count,
    required Color activeColor,
  }) {
    final isSelected = selectedLevel == level;

    return GestureDetector(
      onTap: () => onLevelSelected(level),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : colors.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? activeColor.withValues(alpha: 0.5)
                : colors.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : colors.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.25)
                      : colors.bgSurfaceInset,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? activeColor : colors.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
