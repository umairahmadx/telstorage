/*
 * File: settings_cache_card.dart
 * Description: Widget card displaying local multi-partition cache overview and opening the cache management screen.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/services/app_cache_manager.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/settings/presentation/screens/cache_settings/cache_settings_screen.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';

/// Card component linking to granular cache controls and partition breakdown.
class SettingsCacheCard extends StatefulWidget {
  /// Constructs SettingsCacheCard.
  const SettingsCacheCard({super.key});

  @override
  State<SettingsCacheCard> createState() => _SettingsCacheCardState();
}

class _SettingsCacheCardState extends State<SettingsCacheCard> {
  CachePartitionStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats =
        await ServiceLocator.instance.cacheManager.getPartitionStats();
    if (mounted) {
      setState(() => _stats = stats);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final formattedSize = _stats?.formattedTotal ?? 'Calculating...';

    return AppSurfaceCard(
      onTap: () async {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const CacheSettingsScreen()),
        );
        _loadStats();
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
            child: Icon(Icons.cleaning_services_outlined,
                color: colors.textPrimary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cache & Offline Storage',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$formattedSize • JPEG Thumbnails & Partitions',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              color: colors.textSecondary, size: 20),
        ],
      ),
    );
  }
}
