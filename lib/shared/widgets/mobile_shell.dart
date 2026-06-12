import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_theme.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/browser/screens/browser_screen.dart';
import '../../features/downloads/screens/downloads_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

/// A unified mobile navigation shell that wraps all primary screens with
/// an animated Material 3-style bottom navigation bar.
///
/// Uses [IndexedStack] to persist each tab's state across switches.
/// Child screens can access the shell via [MobileShell.of(context)] to
/// programmatically switch tabs.
class MobileShell extends StatefulWidget {
  final int initialIndex;

  const MobileShell({super.key, this.initialIndex = 0});

  /// Access the [MobileShellState] from a descendant widget to
  /// programmatically switch tabs. Returns null if not inside a MobileShell.
  static MobileShellState? of(BuildContext context) {
    return context.findAncestorStateOfType<MobileShellState>();
  }

  @override
  State<MobileShell> createState() => MobileShellState();
}

class MobileShellState extends State<MobileShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  /// Switch to the tab at [index] programmatically.
  void switchTab(int index) {
    if (index == _currentIndex || index < 0 || index > 3) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  int get currentIndex => _currentIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          HomeScreen(),
          BrowserScreen(),
          DownloadsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _MobileNavBar(
        currentIndex: _currentIndex,
        onTap: switchTab,
      ),
    );
  }
}

// ── Bottom Navigation Bar ─────────────────────────────────────────────────────

class _MobileNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _MobileNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _NavItemData(Icons.home_rounded, 'Home'),
    _NavItemData(Icons.folder_rounded, 'Files'),
    _NavItemData(Icons.download_rounded, 'Downloads'),
    _NavItemData(Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF2A2A45) : const Color(0xFFE0DFFF),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(_items.length, (i) {
              return _NavItem(
                icon: _items[i].icon,
                label: _items[i].label,
                selected: _currentIndex == i,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms, curve: Curves.easeOut);
  }

  // Hold the current index for the selected-check
  int get _currentIndex => currentIndex;
}

// ── Nav Item Data ─────────────────────────────────────────────────────────────

class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData(this.icon, this.label);
}

// ── Individual Nav Item ───────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.primary.withAlpha(25)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                color: selected ? AppTheme.primary : Colors.grey,
                size: 23,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.primary : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
