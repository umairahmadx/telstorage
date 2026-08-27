/*
 * File: cache_overview_card.dart
 * Description: Surface card displaying overall cache utilization percentage, progress bar, and category legends.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/services/app_cache_manager.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/app_surface_card.dart';

/// Renders aggregate cache storage utilization compared against the maximum LRU limit.
class CacheOverviewCard extends StatelessWidget {
  final CachePartitionStats stats;

  const CacheOverviewCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final maxBytes = stats.limitMb * 1024 * 1024;
    final usedFraction = (stats.totalBytes / maxBytes).clamp(0.0, 1.0);

    return AppSurfaceCard(
      padding: const EdgeInsets.all(22),
      radius: 24,
      borderColor: colors.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Local Cache Utilization',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.bgSurfaceInset,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.borderSubtle, width: 1),
                ),
                child: Text(
                  '${(usedFraction * 100).toStringAsFixed(0)}% of Limit',
                  style: TextStyle(
                    color: colors.accentPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RichText(
            text: TextSpan(
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
              children: [
                TextSpan(
                  text: stats.formattedTotal,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(text: ' used of ${stats.limitMb} MB cache limit'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: usedFraction,
              minHeight: 10,
              backgroundColor: colors.bgSurfaceInset,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLegend(colors, colors.fileVideo,
                  'Thumbnails (${stats.formattedThumbnails})'),
              _buildLegend(colors, colors.fileZip,
                  'Partitions (${stats.formattedDatabase})'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(AppColorsExtension colors, Color dotColor, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}
