/*
 * File: cache_limit_selector.dart
 * Description: Multi-choice chip selector configuring the maximum local LRU cache limit.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/services/app_cache_manager.dart';
import '../../../../../../core/theme/app_theme.dart';

/// Choice chip group allowing the user to select from supported cache storage ceilings.
class CacheLimitSelector extends StatelessWidget {
  final int currentLimitMb;
  final ValueChanged<int> onLimitChanged;

  const CacheLimitSelector({
    super.key,
    required this.currentLimitMb,
    required this.onLimitChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppCacheManager.supportedLimitsMb.map((limit) {
        final isSelected = currentLimitMb == limit;
        final label = limit >= 1024
            ? '${(limit / 1024).toStringAsFixed(0)} GB'
            : '$limit MB';

        return ChoiceChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) onLimitChanged(limit);
          },
          selectedColor: colors.accentPrimary,
          backgroundColor: colors.bgSurface,
          labelStyle: TextStyle(
            color: isSelected ? colors.bgPrimary : colors.textPrimary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isSelected ? colors.accentPrimary : colors.borderSubtle,
            ),
          ),
        );
      }).toList(),
    );
  }
}
