/*
 * File: app_status_badge.dart
 * Description: Centralized status pill badge component displaying an icon, label, and accent border.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_theme.dart';

/// Centralized status badge pill widget reused across Overview cards, Settings, and Browser.
class AppStatusBadge extends StatelessWidget {
  /// Badge text label.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional icon color override.
  final Color? iconColor;

  /// Optional text color override.
  final Color? textColor;

  /// Optional background color override.
  final Color? backgroundColor;

  /// Optional border color override.
  final Color? borderColor;

  /// Constructs AppStatusBadge.
  const AppStatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.textColor,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final effectiveIconColor = iconColor ?? colors.accentPrimary;
    final effectiveTextColor = textColor ?? colors.textPrimary;
    final effectiveBg = backgroundColor ?? colors.bgSurfaceInset;
    final effectiveBorder = borderColor ?? colors.borderSubtle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: effectiveBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: effectiveIconColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: effectiveTextColor,
            ),
          ),
        ],
      ),
    );
  }
}
