/*
 * File: tab_visibility_scope.dart
 * Description: InheritedWidget publishing which shell tab is currently visible, so persistent tab content can refresh state when its tab is re-shown.
 */

import 'package:flutter/material.dart';

/// Tabs hosted by the shell body IndexedStack, in child order.
enum ShellTab {
  /// Home dashboard tab.
  home,

  /// File browser tab.
  files,

  /// Downloads and transfers tab.
  downloads,

  /// Settings tab.
  settings,
}

/// Scope exposing the tab currently presented by the shell body.
///
/// Tab content stays mounted inside an IndexedStack, so a card's initState runs
/// once per app launch and never fires again when the user returns to its tab.
/// Cards holding platform-backed state (such as the battery optimization
/// exemption) call [isVisible] from didChangeDependencies to refresh on tab
/// re-entry, because this widget notifies its dependents whenever [visibleTab]
/// changes.
class TabVisibilityScope extends InheritedWidget {
  /// Constructs TabVisibilityScope for the currently visible tab.
  const TabVisibilityScope({
    super.key,
    required this.visibleTab,
    required super.child,
  });

  /// Tab presented to the user right now.
  final ShellTab visibleTab;

  /// Whether [tab] is the tab currently presented to the user.
  ///
  /// Registers a dependency on this scope, so callers are notified through
  /// didChangeDependencies when the shell switches tabs. When there is no scope
  /// in the tree (a screen pushed on its own, outside the shell) the caller is
  /// treated as visible.
  static bool isVisible(BuildContext context, ShellTab tab) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<TabVisibilityScope>();
    return scope == null || scope.visibleTab == tab;
  }

  @override
  bool updateShouldNotify(TabVisibilityScope oldWidget) {
    return visibleTab != oldWidget.visibleTab;
  }
}
