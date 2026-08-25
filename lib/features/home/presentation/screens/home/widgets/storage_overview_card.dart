/*
 * File: storage_overview_card.dart
 * Description: Widget displaying storage capacity bar and aggregated upload/share/download counts using centralized AppStatusBadge.
 */

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';
import 'package:telstorage/shared/widgets/badges/app_status_badge.dart';
import '../viewmodel/home_view_model.dart';

/// Card component showing overall storage metrics and progress bar.
class StorageOverviewCard extends StatelessWidget {
  /// Current HomeState containing storage utilization data.
  final HomeState state;

  /// Constructs StorageOverviewCard.
  const StorageOverviewCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final usedMb = state.storageUsedMb;
    final usedText = usedMb >= 1024
        ? '${(usedMb / 1024).toStringAsFixed(1)} GB'
        : '${usedMb.toStringAsFixed(0)} MB';

    final totalFiles = state.totalFiles;
    final totalShares = state.totalShares;
    final totalDownloads = state.totalDownloads;

    return AppSurfaceCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Storage Overview',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const AppStatusBadge(
                icon: Icons.all_inclusive_rounded,
                label: 'Unlimited',
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: usedText,
                  style: TextStyle(
                      color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const TextSpan(text: ' total cloud storage used'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem(colors, Icons.cloud_upload_outlined, 'Uploaded',
                  '$totalFiles Files'),
              _buildStatItem(
                  colors, Icons.share_rounded, 'Shared', '$totalShares Links'),
              _buildStatItem(colors, Icons.download_rounded, 'Downloads',
                  '$totalDownloads Files'),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, delay: 100.ms)
        .slideY(begin: 0.1, end: 0);
  }

  Widget _buildStatItem(
      AppColorsExtension colors, IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.bgSurfaceInset,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: colors.accentPrimary, size: 18),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
