/*
 * File: mobile_add_action_item.dart
 * Description: Quick action trigger tile used in the global bottom sheet with curved foreground ink ripple.
 */

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Quick action component with rounded icon container and curved ink ripple feedback.
class AddActionItem extends StatelessWidget {
  /// Icon data to display.
  final IconData icon;

  /// Action text label.
  final String label;

  /// Brand/accent color for the action.
  final Color color;

  /// Callback when tapped.
  final VoidCallback onTap;

  /// Constructs AddActionItem.
  const AddActionItem({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final borderRadius = BorderRadius.circular(16);

    return Expanded(
      child: Column(
        children: [
          Material(
            color: color.withValues(alpha: 0.15),
            borderRadius: borderRadius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Center(
                  child: Icon(icon, color: color, size: 28),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
