/*
 * File: app_surface_card.dart
 * Description: Standardized surface container supporting custom corner curves (top-only, bottom-only, all, or flat) and matching foreground ink ripples.
 */

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Centralized surface card component supporting directional curved borders and foreground ink ripples.
class AppSurfaceCard extends StatelessWidget {
  /// Inner child content.
  final Widget child;

  /// Content padding.
  final EdgeInsetsGeometry? padding;

  /// Outer margin.
  final EdgeInsetsGeometry? margin;

  /// Custom directional border radius (e.g. top-only, bottom-only, zero).
  final BorderRadiusGeometry? borderRadius;

  /// Symmetric corner radius (defaults to 14 if borderRadius is unset).
  final double? radius;

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
    this.borderRadius,
    this.radius,
    this.borderColor,
    this.borderWidth = 1,
    this.color,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(radius ?? 14);

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: effectiveRadius,
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: borderWidth),
      ),
      child: child,
    );

    Widget result = Material(
      color: color ?? colors.bgSurface,
      borderRadius: effectiveRadius,
      clipBehavior: Clip.antiAlias,
      child: (onTap != null || onLongPress != null)
          ? InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius:
                  effectiveRadius is BorderRadius ? effectiveRadius : null,
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
