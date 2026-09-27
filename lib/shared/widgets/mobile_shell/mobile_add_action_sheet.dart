/*
 * File: mobile_add_action_sheet.dart
 * Description: Production-grade quick action bottom sheet offering three distinct upload paths:
 * Photos & Videos (zero-copy gallery grid), Upload Files (in-app storage navigator),
 * Upload Folder (system directory picker), and optional New Folder creation in browser view.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors_extension.dart';
import '../../../core/theme/app_icons.dart';

/// Bottom sheet dialog presenting available upload and creation actions in a 2-column grid.
class MobileAddActionSheet extends StatelessWidget {
  /// Callback when user selects Photos & Videos.
  final VoidCallback onMedia;

  /// Callback when user selects Upload Files.
  final VoidCallback onFiles;

  /// Callback when user selects Upload Folder.
  final VoidCallback onFolder;

  /// Callback when user selects New Folder (optional, null when outside browser).
  final VoidCallback? onNewFolder;

  /// Constructs MobileAddActionSheet.
  const MobileAddActionSheet({
    super.key,
    required this.onMedia,
    required this.onFiles,
    required this.onFolder,
    this.onNewFolder,
  });

  /// Displays the add action sheet.
  static void show(
    BuildContext context, {
    required VoidCallback onMedia,
    required VoidCallback onFiles,
    required VoidCallback onFolder,
    VoidCallback? onNewFolder,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MobileAddActionSheet(
        onMedia: onMedia,
        onFiles: onFiles,
        onFolder: onFolder,
        onNewFolder: onNewFolder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();

    final items = [
      _ActionTileData(
        icon: AppIcons.photoLibrary,
        title: 'Photos & Videos',
        subtitle: 'Select from gallery',
        color: colors?.accentPrimary ?? Colors.blue,
        onTap: onMedia,
      ),
      _ActionTileData(
        icon: AppIcons.uploadFile,
        title: 'Upload Files',
        subtitle: 'Browse storage',
        color: colors?.accentPrimary ?? Colors.blue,
        onTap: onFiles,
      ),
      _ActionTileData(
        icon: AppIcons.uploadFolder,
        title: 'Upload Folder',
        subtitle: 'Entire directory',
        color: colors?.accentPrimary ?? Colors.blue,
        onTap: onFolder,
      ),
      if (onNewFolder != null)
        _ActionTileData(
          icon: AppIcons.newFolder,
          title: 'New Folder',
          subtitle: 'Create in cloud',
          color: colors?.warning ?? Colors.amber,
          onTap: onNewFolder!,
        ),
    ];

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: colors?.bgSurface ?? Colors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors?.borderSubtle ?? Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Sheet Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Add to TelStorage',
              style: TextStyle(
                color: colors?.textPrimary ?? Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 2-column action grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.7,
            ),
            itemCount: items.length,
            itemBuilder: (ctx, index) {
              final item = items[index];
              return _ActionCard(
                data: item,
                colors: colors,
                onSelected: () {
                  HapticFeedback.selectionClick();
                  Navigator.pop(context);
                  item.onTap();
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActionTileData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  _ActionTileData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _ActionCard extends StatelessWidget {
  final _ActionTileData data;
  final AppColorsExtension? colors;
  final VoidCallback onSelected;

  const _ActionCard({
    required this.data,
    required this.colors,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(16);

    return Material(
      color: colors?.bgSurfaceInset ?? Colors.white10,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Icon(data.icon, color: data.color, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                data.title,
                style: TextStyle(
                  color: colors?.textPrimary ?? Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                style: TextStyle(
                  color: colors?.textTertiary ?? Colors.white38,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
