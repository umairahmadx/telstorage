/*
 * File: app_user_avatar.dart
 * Description: Centralized user avatar component displaying user initials with configurable size, themed border, and optional status dot.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_theme.dart';

/// Centralized user profile avatar reused across Home, Settings, and Drawer.
class AppUserAvatar extends StatelessWidget {
  /// User full name or username.
  final String? name;

  /// Diameter of the avatar container.
  final double size;

  /// Border width around avatar.
  final double borderWidth;

  /// Whether to display an online / sync status dot on bottom right.
  final bool showStatusDot;

  /// Online or active sync state.
  final bool isOnline;

  /// Constructs AppUserAvatar.
  const AppUserAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.borderWidth = 1.5,
    this.showStatusDot = false,
    this.isOnline = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final initial = (name != null && name!.trim().isNotEmpty)
        ? name!.trim()[0].toUpperCase()
        : 'U';
    final fontSize = size * 0.40;

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colors.bgSurfaceInset,
            shape: BoxShape.circle,
            border: Border.all(
              color: colors.accentPrimary.withValues(alpha: 0.35),
              width: borderWidth,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
            ),
          ),
        ),
        if (showStatusDot)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: isOnline ? colors.success : colors.textTertiary,
                shape: BoxShape.circle,
                border: Border.all(color: colors.bgSurface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
