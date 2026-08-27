/*
 * File: cache_settings_screen.dart
 * Description: Interactive cache control screen displaying segregated partition breakdowns, configurable limits, and LRU cache clearing actions.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/services/app_cache_manager.dart';
import '../../../../../../core/services/service_locator.dart';
import '../../../../../../core/theme/app_theme.dart';
import 'widgets/cache_limit_selector.dart';
import 'widgets/cache_overview_card.dart';
import 'widgets/cache_partition_card.dart';

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
    final stats =
        await ServiceLocator.instance.cacheManager.getPartitionStats();
    if (mounted) {
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    }
  }

  Future<void> _changeLimit(int limitMb) async {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    await ServiceLocator.instance.cacheManager.setCacheLimitMb(limitMb);
    await _loadStats();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cache limit set to $limitMb MB'),
          backgroundColor: colors.bgSurfaceInset,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearPartition({
    required String title,
    required Future<void> Function() onClear,
  }) async {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear $title?'),
        content: Text(
          'Are you sure you want to clear the $title? Cached items will be re-downloaded as needed.',
        ),
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
            backgroundColor: colors.success,
          ),
        );
      }
    }
  }

  Future<void> _clearAll() async {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Local Cache?'),
        content: const Text(
          'This will clear all thumbnail previews, folder partition caches, and temp transfer files. Remote cloud data on Telegram remains 100% safe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colors.error),
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
          SnackBar(
            content: const Text('All local cache flushed successfully'),
            backgroundColor: colors.success,
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
                if (_stats != null) CacheOverviewCard(stats: _stats!),
                const SizedBox(height: 24),
                _sectionLabel(colors, 'MAXIMUM CACHE LIMIT (LRU)'),
                const SizedBox(height: 12),
                CacheLimitSelector(
                  currentLimitMb:
                      _stats?.limitMb ?? AppCacheManager.defaultCacheLimitMb,
                  onLimitChanged: _changeLimit,
                ),
                const SizedBox(height: 28),
                _sectionLabel(colors, 'PARTITION BREAKDOWN & CONTROLS'),
                const SizedBox(height: 12),
                CachePartitionCard(
                  icon: Icons.photo_library_outlined,
                  iconColor: colors.fileVideo,
                  title: '400px WebP Thumbnails',
                  subtitle:
                      '${_stats?.thumbnailCount ?? 0} cached media previews (<=50KB)',
                  sizeText: _stats?.formattedThumbnails ?? '0 B',
                  onClear: () => _clearPartition(
                    title: 'Thumbnails Cache',
                    onClear: ServiceLocator
                        .instance.cacheManager.clearThumbnailCache,
                  ),
                ),
                const SizedBox(height: 12),
                CachePartitionCard(
                  icon: Icons.folder_copy_outlined,
                  iconColor: colors.fileZip,
                  title: 'Database & Folder Partitions',
                  subtitle: 'Hive index & LRU folder metadata partitions',
                  sizeText: _stats?.formattedDatabase ?? '0 B',
                  onClear: () => _clearPartition(
                    title: 'Folder Partitions Cache',
                    onClear: ServiceLocator
                        .instance.cacheManager.clearFolderPartitionCache,
                  ),
                ),
                const SizedBox(height: 12),
                CachePartitionCard(
                  icon: Icons.sync_problem_rounded,
                  iconColor: colors.filePdf,
                  title: 'Temporary Transfer Chunks',
                  subtitle: 'Temporary in-flight upload/download chunks',
                  sizeText: _stats?.formattedTemp ?? '0 B',
                  onClear: () => _clearPartition(
                    title: 'Temporary Transfer Cache',
                    onClear:
                        ServiceLocator.instance.cacheManager.clearTempCache,
                  ),
                ),
                const SizedBox(height: 36),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side:
                        BorderSide(color: colors.error.withValues(alpha: 0.47)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded),
                  label: const Text(
                    'Clear All Local Cache',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _clearAll,
                ),
                const SizedBox(height: 40),
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
