/*
 * File: settings_profile_card.dart
 * Description: Profile header card displaying user avatar, email, and connection status using centralized shared widgets.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';
import 'package:telstorage/shared/widgets/badges/app_status_badge.dart';
import 'package:telstorage/shared/widgets/user/app_user_avatar.dart';

/// Card component showing authenticated user profile details.
class SettingsProfileCard extends StatelessWidget {
  /// Current HomeState containing user info.
  final HomeState state;

  /// Constructs SettingsProfileCard.
  const SettingsProfileCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final name = state.userName ?? 'User';
    final email = state.userEmail ?? '';

    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Row(
        children: [
          AppUserAvatar(
            name: name,
            size: 56,
            borderWidth: 2,
            showStatusDot: true,
            isOnline: true,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const AppStatusBadge(
                  icon: Icons.check_circle_rounded,
                  label: 'Connected to Telegram',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
