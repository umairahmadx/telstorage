import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_surface_card.dart';
import '../../bloc/home_cubit.dart';

class StorageOverviewCard extends StatelessWidget {
  final HomeState state;

  const StorageOverviewCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final usedMb = state.storageUsedMb;
    final limitMb = state.metadata?.storageLimitMb ?? 102400; // fallback 100GB
    final usedText = usedMb >= 1024
        ? '${(usedMb / 1024).toStringAsFixed(1)} GB'
        : '${usedMb.toStringAsFixed(0)} MB';

    final totalFiles = state.totalFiles;
    final totalShares = state.totalShares;
    final totalDownloads = state.totalDownloads;

    return AppSurfaceCard(
      padding: const EdgeInsets.all(24),
      radius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Storage Overview',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: usedText,
                  style: TextStyle(
                      color: colors.textPrimary, fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' of Unlimited used'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (usedMb / limitMb).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: colors.bgSurfaceInset,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
            ),
          ),
          const SizedBox(height: 24),
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
    return Container(
      width: 95,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: colors.bgSurfaceInset,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.textPrimary, size: 20),
          const SizedBox(height: 8),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(color: colors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}
