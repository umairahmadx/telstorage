import 'package:flutter/material.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../utils/responsive.dart';

/// Desktop-only persistent navigation rail / drawer wrapper.
/// On mobile this is not used — screens handle their own AppBar.
class AppShell extends StatelessWidget {
  final Widget child;
  final int selectedIndex; // 0=home, 1=browser, 2=settings
  final bool showFab;
  final VoidCallback? onFabPressed;
  final String fabLabel;
  final IconData fabIcon;

  const AppShell({
    super.key,
    required this.child,
    this.selectedIndex = 0,
    this.showFab = false,
    this.onFabPressed,
    this.fabLabel = 'Upload',
    this.fabIcon = Icons.cloud_upload_rounded,
  });

  @override
  Widget build(BuildContext context) {
    if (Responsive.isMobile(context)) {
      // Mobile: just return child — mobile screens have their own AppBar + FAB
      return child;
    }
    // Desktop/Tablet: persistent nav rail + content
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          _DesktopRail(selectedIndex: selectedIndex),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DesktopRail extends StatelessWidget {
  final int selectedIndex;
  const _DesktopRail({required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.sizeOf(context).width > 1200;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isWide ? 240 : 72,
      color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Logo
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isWide ? 20 : 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, Color(0xFFA78BFA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_done_rounded,
                      color: Colors.white, size: 22),
                ),
                if (isWide) ...[
                  const SizedBox(width: 12),
                  Text(
                    'TelStorage',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Nav items
          _NavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            isSelected: selectedIndex == 0,
            isWide: isWide,
            onTap: () =>
                Navigator.of(context).pushReplacementNamed(AppRouter.home),
          ),
          _NavItem(
            icon: Icons.folder_rounded,
            label: 'Files',
            isSelected: selectedIndex == 1,
            isWide: isWide,
            onTap: () =>
                Navigator.of(context).pushReplacementNamed(AppRouter.browser),
          ),
          _NavItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            isSelected: selectedIndex == 2,
            isWide: isWide,
            onTap: () => Navigator.of(context).pushNamed(AppRouter.settings),
          ),
          const Spacer(),
          // Logout
          _NavItem(
            icon: Icons.logout_rounded,
            label: 'Log out',
            isSelected: false,
            isWide: isWide,
            color: AppTheme.error,
            onTap: () async {
              final nav = Navigator.of(context);
              await AuthService.instance.logout();
              nav.pushReplacementNamed(AppRouter.login);
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isWide;
  final Color? color;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isWide,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppTheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: isSelected ? AppTheme.primary.withAlpha(30) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isWide ? 14 : 12,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? accent
                      : (isDark ? Colors.white60 : Colors.black54),
                  size: 22,
                ),
                if (isWide) ...[
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? accent
                          : (isDark ? Colors.white70 : Colors.black87),
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
