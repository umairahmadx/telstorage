/*
 * File: home_greeting_card.dart
 * Description: Widget displaying user greeting banner and real-time sync indicator using centralized AppUserAvatar.
 */

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'package:telstorage/shared/widgets/user/app_user_avatar.dart';

/// Card component showing welcoming header with user initials and status.
class HomeGreetingCard extends StatelessWidget {
  /// Current HomeState containing user details and sync information.
  final HomeState state;

  /// Constructs HomeGreetingCard.
  const HomeGreetingCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final name = state.userName ?? 'User';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Good morning, $name',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(width: 8),
                    const Text('👋', style: TextStyle(fontSize: 20)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  state.isSyncing
                      ? state.syncStatus
                      : 'Your files are safe and synced.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          AppUserAvatar(
            name: name,
            size: 48,
            showStatusDot: true,
            isOnline: !state.isSyncing,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }
}
