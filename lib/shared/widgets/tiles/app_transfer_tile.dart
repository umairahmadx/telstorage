/*
 * File: app_transfer_tile.dart
 * Description: Centralized transfer progress tile component displaying active upload and download tasks with progress bar and controls.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';
import 'package:telstorage/shared/widgets/thumbnail_widget.dart';

/// Centralized transfer item tile for active background upload and download queues.
class AppTransferTile extends StatelessWidget {
  /// Associated transfer task.
  final TransferTask task;

  /// Optional custom directional border radius.
  final BorderRadiusGeometry? borderRadius;

  /// Callback when pause action is pressed.
  final VoidCallback onPause;

  /// Callback when resume action is pressed.
  final VoidCallback onResume;

  /// Callback when cancel action is pressed.
  final VoidCallback onCancel;

  /// Constructs AppTransferTile.
  const AppTransferTile({
    super.key,
    required this.task,
    this.borderRadius,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  Widget _buildBadge(SmartBadgeInfo badge) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: badge.bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Icon(
          badge.icon,
          color: badge.iconColor,
          size: 22,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final badge = SmartBadgeInfo.resolve(task.name, '', colors);

    final subtitleParts = <String>[];
    if (task.status == TransferStatus.waiting ||
        task.status == TransferStatus.pending) {
      if (task.sizeMb > 0) {
        subtitleParts.add('${task.sizeMb.toStringAsFixed(1)} MB');
      }
      subtitleParts.add(task.currentStage ?? 'Waiting in queue…');
    } else {
      final pct = (task.progress * 100).toInt();
      subtitleParts.add('$pct%');
      if (task.sizeMb > 0) {
        final transferred = (task.progress * task.sizeMb).toStringAsFixed(1);
        final total = task.sizeMb.toStringAsFixed(1);
        subtitleParts.add('$transferred / $total MB');
      }
      if (task.speedKbps > 0 &&
          task.speedKbps.isFinite &&
          !task.speedKbps.isNaN) {
        subtitleParts
            .add('${(task.speedKbps / 1024).toStringAsFixed(1)} MB/s');
      }
      if (task.currentStage != null && task.currentStage!.isNotEmpty) {
        subtitleParts.add(task.currentStage!);
      }
    }
    final subtitle = subtitleParts.join(' • ');

    final cachedThumb = ServiceLocator.instance.isInitialized
        ? ServiceLocator.instance.thumbnailRepository
            .getMemoryCachedBytes(task.id)
        : null;

    final Widget leadingWidget = cachedThumb != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              cachedThumb,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildBadge(badge),
            ),
          )
        : _buildBadge(badge);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        borderRadius: borderRadius ?? BorderRadius.circular(12),
        borderColor: colors.borderSubtle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                leadingWidget,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (task.status == TransferStatus.uploading ||
                    task.status == TransferStatus.downloading)
                  IconButton(
                    icon: Icon(AppIcons.pauseCircle,
                        color: colors.textSecondary, size: 22),
                    tooltip: 'Pause',
                    onPressed: onPause,
                  )
                else if (task.status == TransferStatus.paused)
                  IconButton(
                    icon: Icon(AppIcons.playCircle,
                        color: colors.accentPrimary, size: 22),
                    tooltip: 'Resume',
                    onPressed: onResume,
                  ),
                IconButton(
                  icon: Icon(AppIcons.cancel,
                      color: colors.error, size: 22),
                  tooltip: 'Cancel',
                  onPressed: onCancel,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: task.progress.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: colors.bgSurfaceInset,
                valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
