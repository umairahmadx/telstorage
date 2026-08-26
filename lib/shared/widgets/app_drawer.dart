/*
 * File: app_drawer.dart
 * Description: Sidebar navigation drawer for direct destination routing across views.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/navigation/navigation_intent.dart';
import '../../core/services/service_locator.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';


/// Navigation drawer widget providing primary application destinations.
class AppDrawer extends StatelessWidget {
  /// Currently active tab index.
  final int currentIndex;

  /// Callback when a tab item is clicked.
  final Function(int) onTabSelected;

  /// Constructs AppDrawer.
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
                          AppIcons.cloudQueue,
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
              icon: AppIcons.navHomeOutlined,
              label: 'Home',
              isSelected: currentIndex == 0,
              onTap: () {
                Navigator.pop(context);
                ServiceLocator.instance.navigation
                    .navigateTo(AppDestination.home);
              },
            ),
            _DrawerItem(
              icon: AppIcons.navFiles,
              label: 'Files',
              isSelected: currentIndex == 1,
              onTap: () {
                Navigator.pop(context);
                ServiceLocator.instance.navigation
                    .navigateTo(AppDestination.files);
              },
            ),
            _DrawerItem(
              icon: AppIcons.navDownloads,
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
              icon: AppIcons.navUploads,
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
              icon: AppIcons.navShared,
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
              icon: AppIcons.navSettings,
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

/// Helper navigation item in the drawer list.
class _DrawerItem extends StatelessWidget {
  /// Icon for the drawer row.
  final IconData icon;

  /// Text title for the drawer row.
  final String label;

  /// Whether this row is currently selected.
  final bool isSelected;

  /// Tap callback.
  final VoidCallback onTap;

  /// Constructs _DrawerItem.
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
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
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
      ),
    );
  }
}
