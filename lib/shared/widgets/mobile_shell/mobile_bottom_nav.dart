/// File: mobile_bottom_nav.dart
/// Description: Component and logic definition for mobile_bottom_nav.dart in TelStorage.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';

class MobileNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const MobileNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: 0.5),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              NavItem(
                icon: AppIcons.navHome,
                label: 'Home',
                selected: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              NavItem(
                icon: AppIcons.navFiles,
                label: 'Files',
                selected: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              const SizedBox(width: 60), // Space for FAB
              NavItem(
                icon: AppIcons.navTransfer,
                label: 'Transfer',
                selected: currentIndex == 3,
                onTap: () => onTap(3),
              ),
              NavItem(
                icon: AppIcons.more,
                label: 'More',
                selected: currentIndex == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
          Positioned(
            top: -20,
            child: GestureDetector(
              onTap: () => onTap(2),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: colors.accentPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: colors.textPrimary.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  AppIcons.add,
                  color: colors.bgPrimary,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, curve: Curves.easeOut);
  }
}

class NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? colors.accentPrimary : colors.textTertiary,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? colors.accentPrimary : colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
