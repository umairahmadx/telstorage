import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_surface_card.dart';
import '../../../home/bloc/home_cubit.dart';
import '../storage_details_screen.dart';

class SettingsStorageCard extends StatelessWidget {
  final HomeState state;

  const SettingsStorageCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final usedMb = state.storageUsedMb;
    final usedText = usedMb >= 1024
        ? '${(usedMb / 1024).toStringAsFixed(1)} GB'
        : '${usedMb.toStringAsFixed(0)} MB';

    return AppSurfaceCard(
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const StorageDetailsScreen()),
        );
      },
      padding: const EdgeInsets.all(18),
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
            child: Icon(Icons.cloud_outlined, color: colors.textPrimary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cloud Storage',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$usedText used • Unlimited Available',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
        ],
      ),
    );
  }
}
