/*
 * File: app_section_label.dart
 * Description: Centralized typography component rendering standardized uppercase section headers with optional action trigger.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_theme.dart';

/// Centralized uppercase section header widget reused across all screens.
class AppSectionLabel extends StatelessWidget {
  /// Section title text.
  final String label;

  /// Optional trailing action button text (e.g. "See All", "Clear").
  final String? actionText;

  /// Optional callback when action text is tapped.
  final VoidCallback? onActionTap;

  /// Outer padding.
  final EdgeInsetsGeometry padding;

  /// Constructs AppSectionLabel.
  const AppSectionLabel({
    super.key,
    required this.label,
    this.actionText,
    this.onActionTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          if (actionText != null && onActionTap != null)
            InkWell(
              onTap: onActionTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  actionText!,
                  style: TextStyle(
                    color: colors.accentPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
