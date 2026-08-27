/*
 * File: app_action_card.dart
 * Description: Centralized interactive action card component displaying leading icon container, title, subtitle, and trailing widget.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';

/// Centralized action card used across Settings, Control Center, and Tools screens.
class AppActionCard extends StatelessWidget {
  /// Leading icon.
  final IconData icon;

  /// Optional leading icon color override.
  final Color? iconColor;

  /// Card primary title.
  final String title;

  /// Optional card description / subtitle.
  final String? subtitle;

  /// Optional trailing widget (defaults to chevron right).
  final Widget? trailing;

  /// Tap callback.
  final VoidCallback? onTap;

  /// Padding around content.
  final EdgeInsetsGeometry padding;

  /// Constructs AppActionCard.
  const AppActionCard({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final effectiveIconColor = iconColor ?? colors.textPrimary;

    return AppSurfaceCard(
      onTap: onTap,
      padding: padding,
      radius: 20,
      borderColor: colors.borderSubtle,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: effectiveIconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            Icon(Icons.chevron_right_rounded,
                color: colors.textSecondary, size: 20),
        ],
      ),
    );
  }
}
