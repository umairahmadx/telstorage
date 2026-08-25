/*
 * File: app_surface_card.dart
 * Description: Standardized surface container with rounded corners, optional border, and curved foreground ripple feedback.
 */

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Centralized surface card component supporting curved borders and foreground ink ripples.
class AppSurfaceCard extends StatelessWidget {
  /// Inner child content.
  final Widget child;

  /// Content padding.
  final EdgeInsetsGeometry? padding;

  /// Outer margin.
  final EdgeInsetsGeometry? margin;

  /// Corner radius (defaults to 20).
  final double radius;

  /// Border outline color.
  final Color? borderColor;

  /// Border line thickness.
  final double borderWidth;

  /// Card surface fill color.
  final Color? color;

  /// Tap callback triggering foreground ripple.
  final VoidCallback? onTap;

  /// Long press callback.
  final VoidCallback? onLongPress;

  /// Constructs AppSurfaceCard.
  const AppSurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 20,
    this.borderColor,
    this.borderWidth = 1,
    this.color,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final borderRadius = BorderRadius.circular(radius);

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: borderWidth),
      ),
      child: child,
    );

    Widget result = Material(
      color: color ?? colors.bgSurface,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: (onTap != null || onLongPress != null)
          ? InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: borderRadius,
              child: content,
            )
          : content,
    );

    if (margin != null) {
      result = Padding(padding: margin!, child: result);
    }

    return result;
  }
}
