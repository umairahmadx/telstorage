import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/navigation/navigation_intent.dart';

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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.accentPrimary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.cloud_queue_rounded,
                          color: colors.bgPrimary,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'TelStorage',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
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
                ServiceLocator.instance.navigation
                    .navigateTo(AppDestination.home);
              },
            ),
            _DrawerItem(
              icon: Icons.folder_outlined,
              label: 'Files',
              isSelected: currentIndex == 1,
              onTap: () {
                Navigator.pop(context);
                ServiceLocator.instance.navigation
                    .navigateTo(AppDestination.files);
              },
            ),
            _DrawerItem(
              icon: Icons.download_rounded,
              label: 'Downloads',
              isSelected: currentIndex == 3 &&
                  ServiceLocator.instance.navigation.lastTransferTab == 0,
              onTap: () {
                Navigator.pop(context);
                ServiceLocator.instance.navigation
                    .navigateTo(AppDestination.transferDownloads);
              },
            ),
            _DrawerItem(
              icon: Icons.cloud_upload_outlined,
              label: 'Uploads',
              isSelected: currentIndex == 3 &&
                  ServiceLocator.instance.navigation.lastTransferTab == 1,
              onTap: () {
                Navigator.pop(context);
                ServiceLocator.instance.navigation
                    .navigateTo(AppDestination.transferUploads);
              },
            ),
            _DrawerItem(
              icon: Icons.share_rounded,
              label: 'Shared',
              isSelected: currentIndex == 3 &&
                  ServiceLocator.instance.navigation.lastTransferTab == 2,
              onTap: () {
                Navigator.pop(context);
                ServiceLocator.instance.navigation
                    .navigateTo(AppDestination.transferShared);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Divider(color: colors.borderSubtle),
            ),
            _DrawerItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              isSelected: currentIndex == 4,
              onTap: () {
                Navigator.pop(context);
                ServiceLocator.instance.navigation
                    .navigateTo(AppDestination.settings);
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
