/// File: browser_sort_sheet.dart
/// Description: Modal bottom sheet allowing user to configure file sorting and folder grouping.
library;

import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../viewmodel/browser_event.dart';

/// Modal bottom sheet for changing sorting criteria and grouping options.
class BrowserSortSheet extends StatelessWidget {
  /// Currently active sort option.
  final BrowserSortOption currentSort;

  /// Whether sorting is in ascending order.
  final bool isAscending;

  /// Currently active grouping mode.
  final BrowserGroupOption currentGroup;

  /// Callback when a new sort option is selected.
  final ValueChanged<BrowserSortOption> onSortChanged;

  /// Callback when a new grouping option is selected.
  final ValueChanged<BrowserGroupOption> onGroupChanged;

  /// Constructs BrowserSortSheet.
  const BrowserSortSheet({
    super.key,
    required this.currentSort,
    required this.isAscending,
    required this.currentGroup,
    required this.onSortChanged,
    required this.onGroupChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sort & Group',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'SORT BY',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            ListTile(
              title: const Text('Name'),
              trailing: currentSort == BrowserSortOption.name
                  ? Icon(
                      isAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: colors.accentPrimary)
                  : null,
              onTap: () {
                onSortChanged(BrowserSortOption.name);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Date'),
              trailing: currentSort == BrowserSortOption.date
                  ? Icon(
                      isAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: colors.accentPrimary)
                  : null,
              onTap: () {
                onSortChanged(BrowserSortOption.date);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Size'),
              trailing: currentSort == BrowserSortOption.size
                  ? Icon(
                      isAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      color: colors.accentPrimary)
                  : null,
              onTap: () {
                onSortChanged(BrowserSortOption.size);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            Text(
              'GROUP BY',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            ListTile(
              title: const Text('Folders First'),
              trailing: currentGroup == BrowserGroupOption.foldersFirst
                  ? Icon(Icons.check_rounded, color: colors.accentPrimary)
                  : null,
              onTap: () {
                onGroupChanged(BrowserGroupOption.foldersFirst);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('None'),
              trailing: currentGroup == BrowserGroupOption.mixed
                  ? Icon(Icons.check_rounded, color: colors.accentPrimary)
                  : null,
              onTap: () {
                onGroupChanged(BrowserGroupOption.mixed);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
