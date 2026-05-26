import 'package:flutter/material.dart';

/// Breakpoints matching Material 3 adaptive layout guidelines.
class Responsive {
  static const _mobileMax  = 600.0;
  static const _tabletMax  = 960.0;

  static bool isMobile(BuildContext ctx)  => MediaQuery.sizeOf(ctx).width < _mobileMax;
  static bool isTablet(BuildContext ctx)  => MediaQuery.sizeOf(ctx).width >= _mobileMax && MediaQuery.sizeOf(ctx).width < _tabletMax;
  static bool isDesktop(BuildContext ctx) => MediaQuery.sizeOf(ctx).width >= _tabletMax;

  /// Returns [mobile] on narrow, [desktop] on wide screens.
  static T value<T>(BuildContext ctx, {required T mobile, required T desktop, T? tablet}) {
    final w = MediaQuery.sizeOf(ctx).width;
    if (w >= _tabletMax) return desktop;
    if (w >= _mobileMax) return tablet ?? desktop;
    return mobile;
  }
}
