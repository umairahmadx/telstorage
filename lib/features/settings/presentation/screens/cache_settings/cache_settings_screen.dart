/*
 * File: cache_settings_screen.dart
 * Description: Interactive cache control screen displaying segregated partition breakdowns, configurable limits, and LRU cache clearing actions.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/services/app_cache_manager.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';

/// Screen component rendering granular multi-partition cache metrics and limits.
class CacheSettingsScreen extends StatefulWidget {
  /// Constructs CacheSettingsScreen.
  const CacheSettingsScreen({super.key});

  @override
  State<CacheSettingsScreen> createState() => _CacheSettingsScreenState();
}

class _CacheSettingsScreenState extends State<CacheSettingsScreen> {
  CachePartitionStats? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    final stats = await ServiceLocator.instance.cacheManager.getPartitionStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  Future<void> _changeLimit(int limitMb) async {
    await ServiceLocator.instance.cacheManager.setCacheLimitMb(limitMb);
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cache limit set to $limitMb MB'),
          backgroundColor: AppTheme.grey800,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearPartition({
    required String title,
    required Future<void> Function() onClear,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear $title?'),
        content: Text('Are you sure you want to clear the $title? Cached items will be re-downloaded as needed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await onClear();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$title cleared successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Local Cache?'),
        content: const Text('This will clear all thumbnail previews, folder partition caches, and temp transfer files. Remote cloud data on Telegram remains 100% safe.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ServiceLocator.instance.cacheManager.clearAllCache();
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All local cache flushed successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Cache & Storage',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: colors.textPrimary),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildOverviewCard(colors),
                const SizedBox(height: 24),
                _sectionLabel(colors, 'MAXIMUM CACHE LIMIT (LRU)'),
                const SizedBox(height: 12),
                _buildLimitSelector(colors),
                const SizedBox(height: 28),
                _sectionLabel(colors, 'PARTITION BREAKDOWN & CONTROLS'),
                const SizedBox(height: 12),
                _buildPartitionCard(
                  colors: colors,
                  icon: Icons.photo_library_outlined,
                  iconColor: colors.fileVideo,
                  title: '400px WebP Thumbnails',
                  subtitle: '${_stats?.thumbnailCount ?? 0} cached media previews (<=50KB)',
                  sizeText: _stats?.formattedThumbnails ?? '0 B',
                  onClear: () => _clearPartition(
                    title: 'Thumbnails Cache',
                    onClear: ServiceLocator.instance.cacheManager.clearThumbnailCache,
                  ),
                ),
                const SizedBox(height: 12),
                _buildPartitionCard(
                  colors: colors,
                  icon: Icons.folder_copy_outlined,
                  iconColor: colors.fileZip,
                  title: 'Database & Folder Partitions',
                  subtitle: 'Hive index & LRU folder metadata partitions',
                  sizeText: _stats?.formattedDatabase ?? '0 B',
                  onClear: () => _clearPartition(
                    title: 'Folder Partitions Cache',
                    onClear: ServiceLocator.instance.cacheManager.clearFolderPartitionCache,
                  ),
                ),
                const SizedBox(height: 12),
                _buildPartitionCard(
                  colors: colors,
                  icon: Icons.sync_problem_rounded,
                  iconColor: colors.filePdf,
                  title: 'Temporary Transfer Chunks',
                  subtitle: 'Temporary in-flight upload/download chunks',
                  sizeText: _stats?.formattedTemp ?? '0 B',
                  onClear: () => _clearPartition(
                    title: 'Temporary Transfer Cache',
                    onClear: ServiceLocator.instance.cacheManager.clearTempCache,
                  ),
                ),
                const SizedBox(height: 36),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side: BorderSide(color: colors.error.withAlpha(120)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: const Text('Clear All Local Cache', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _clearAll,
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildOverviewCard(AppColorsExtension colors) {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();

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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
              _buildLegend(colors, colors.fileVideo, 'Thumbnails (${stats.formattedThumbnails})'),
              _buildLegend(colors, colors.fileZip, 'Partitions (${stats.formattedDatabase})'),
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

  Widget _buildLimitSelector(AppColorsExtension colors) {
    final currentLimit = _stats?.limitMb ?? AppCacheManager.defaultCacheLimitMb;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppCacheManager.supportedLimitsMb.map((limit) {
        final isSelected = currentLimit == limit;
        final label = limit >= 1024 ? '${(limit / 1024).toStringAsFixed(0)} GB' : '$limit MB';

        return ChoiceChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) _changeLimit(limit);
          },
          selectedColor: colors.accentPrimary,
          backgroundColor: colors.bgSurface,
          labelStyle: TextStyle(
            color: isSelected ? colors.bgPrimary : colors.textPrimary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isSelected ? colors.accentPrimary : colors.borderSubtle,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPartitionCard({
    required AppColorsExtension colors,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String sizeText,
    required VoidCallback onClear,
  }) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(16),
      radius: 18,
      borderColor: colors.borderSubtle,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                sizeText,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              InkWell(
                onTap: onClear,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: colors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(AppColorsExtension colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}
