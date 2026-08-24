/// File: settings_profile_card.dart
/// Description: Profile header card displaying user initials, email, and connection status.
library;

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';

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
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              shape: BoxShape.circle,
              border: Border.all(
                color: colors.accentPrimary.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
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
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
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
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Connected to Telegram Cloud',
                    style: TextStyle(
                      color: colors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
