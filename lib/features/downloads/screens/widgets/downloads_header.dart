import 'package:flutter/material.dart';
import '../../../../shared/widgets/app_search_field.dart';
import '../../../../shared/widgets/app_segmented_control.dart';
import '../../../../shared/widgets/mobile_shell.dart';

class DownloadsHeader extends StatelessWidget implements PreferredSizeWidget {
  final int activeTab;
  final bool isSearching;
  final TextEditingController searchCtrl;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onSearchQueryChanged;
  final VoidCallback onClearCompleted;

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
