import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class AppDrawer extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTabSelected;

  const AppDrawer({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    
    return Drawer(
      backgroundColor: colors.bgPrimary,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.accentPrimary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Image.asset(
                      'assets/images/logo.png',
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'TelStorage',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _DrawerItem(
              icon: Icons.home_outlined,
              label: 'Home',
              isSelected: currentIndex == 0,
              onTap: () {
                Navigator.pop(context);
                onTabSelected(0);
              },
            ),
            _DrawerItem(
              icon: Icons.folder_outlined,
              label: 'Files',
              isSelected: currentIndex == 1,
              onTap: () {
                Navigator.pop(context);
                onTabSelected(1);
              },
            ),
            _DrawerItem(
              icon: Icons.file_download_outlined,
              label: 'Downloads',
              isSelected: false,
              onTap: () {
                Navigator.pop(context);
                onTabSelected(3);
              },
            ),
            _DrawerItem(
              icon: Icons.file_upload_outlined,
              label: 'Uploads',
              isSelected: false,
              onTap: () {
                Navigator.pop(context);
                onTabSelected(3);
              },
            ),
            _DrawerItem(
              icon: Icons.people_outline_rounded,
              label: 'Shared',
              isSelected: false,
              onTap: () {
                Navigator.pop(context);
                onTabSelected(3);
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Divider(color: Colors.white10),
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              isSelected: currentIndex == 4,
              onTap: () {
                Navigator.pop(context);
                onTabSelected(4);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(
        icon,
        color: isSelected ? colors.accentPrimary : colors.textSecondary,
        size: 24,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: isSelected ? colors.accentPrimary : colors.textSecondary,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}
