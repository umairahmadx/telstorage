import 'package:flutter/material.dart';
import '../../core/services/service_locator.dart';
import '../../core/theme/app_theme.dart';

/// Shows a bottom sheet for the user to pick a destination folder.
/// Returns the chosen folder ID, or null if the user chose Root.
/// Returns `false` if the user dismissed without choosing.
Future<String?> showFolderPicker(
  BuildContext context, {
  String? currentFolderId,
  String title = 'Upload to…',
}) async {
  return showModalBottomSheet<String?>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _FolderPickerSheet(
      currentFolderId: currentFolderId,
      title: title,
    ),
  );
}

class _FolderPickerSheet extends StatelessWidget {
  final String? currentFolderId;
  final String title;
  const _FolderPickerSheet({this.currentFolderId, required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final folders = ServiceLocator.instance.hive.allFolders
        .where((f) => f.id != currentFolderId)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ───────────────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // ── Title ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                const Icon(Icons.drive_file_move_rounded,
                    color: AppTheme.primary),
                const SizedBox(width: 10),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          // ── Root option ─────────────────────────────────────────────────
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                _FolderItem(
                  icon: Icons.home_rounded,
                  name: 'Root (No folder)',
                  color: AppTheme.secondary,
                  isSelected: currentFolderId == null,
                  onTap: () => Navigator.pop(context, null),
                ),
                ...folders.map((f) => _FolderItem(
                      icon: Icons.folder_rounded,
                      name: f.name,
                      color: AppTheme.warning,
                      isSelected: f.id == currentFolderId,
                      onTap: () => Navigator.pop(context, f.id),
                    )),
                if (folders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    child: Text(
                      'No folders yet. Create one in the browser.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderItem extends StatelessWidget {
  final IconData icon;
  final String name;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _FolderItem({
    required this.icon,
    required this.name,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(name, style: Theme.of(context).textTheme.labelLarge),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded,
              color: AppTheme.primary, size: 20)
          : null,
      onTap: onTap,
    );
  }
}
