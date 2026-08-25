/*
 * File: downloads_header.dart
 * Description: Header app bar and segmented control for switching between Downloads, Uploads, and Shared Links.
 */

import 'package:flutter/material.dart';
import '../../../../../../shared/widgets/app_search_field.dart';
import '../../../../../../shared/widgets/app_segmented_control.dart';
import '../../../../../../shared/widgets/mobile_shell.dart';

/// Preferred-size app bar header containing navigation title and segmented tab switch.
class DownloadsHeader extends StatelessWidget implements PreferredSizeWidget {
  /// Currently selected tab index.
  final int activeTab;

  /// Whether search field is displayed.
  final bool isSearching;

  /// Search input text controller.
  final TextEditingController searchCtrl;

  /// Callback when tab selection changes.
  final ValueChanged<int> onTabChanged;

  /// Callback to toggle search mode.
  final VoidCallback onToggleSearch;

  /// Callback on search query changes.
  final ValueChanged<String> onSearchQueryChanged;

  /// Callback to clear completed jobs.
  final VoidCallback onClearCompleted;

  /// Constructs DownloadsHeader.
  const DownloadsHeader({
    super.key,
    required this.activeTab,
    required this.isSearching,
    required this.searchCtrl,
    required this.onTabChanged,
    required this.onToggleSearch,
    required this.onSearchQueryChanged,
    required this.onClearCompleted,
  });

  @override
  Size get preferredSize => Size.fromHeight(isSearching ? 160 : 120);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => MobileShell.of(context)?.openDrawer(),
          ),
          title: const Text('Transfers'),
          actions: [
            IconButton(
              icon: Icon(
                isSearching ? Icons.close_rounded : Icons.search_rounded,
              ),
              onPressed: onToggleSearch,
            ),
            if (activeTab == 0)
              IconButton(
                icon: const Icon(Icons.delete_sweep_rounded),
                tooltip: 'Clear Completed',
                onPressed: onClearCompleted,
              ),
          ],
        ),
        if (isSearching)
          AppSearchField(
            hintText: 'Search downloads…',
            controller: searchCtrl,
            autofocus: true,
            onChanged: onSearchQueryChanged,
          )
        else
          AppSegmentedControl<int>(
            segments: const [
              AppSegment(value: 0, label: 'Downloads'),
              AppSegment(value: 1, label: 'Uploads'),
              AppSegment(value: 2, label: 'Shared Links'),
            ],
            value: activeTab,
            onChanged: onTabChanged,
          ),
      ],
    );
  }
}
