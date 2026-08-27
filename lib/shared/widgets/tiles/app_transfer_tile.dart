/*
 * File: app_transfer_tile.dart
 * Description: Centralized transfer progress tile component displaying active upload and download tasks with progress bar and controls.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';

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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

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
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.accentPrimary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    task.type == TransferType.upload
                        ? Icons.cloud_upload_rounded
                        : Icons.cloud_download_rounded,
                    color: colors.accentPrimary,
                    size: 20,
                  ),
                ),
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
                      const SizedBox(height: 2),
                      Text(
                        '${(task.progress * 100).toInt()}% • ${task.currentStage}',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (task.status == TransferStatus.uploading ||
                    task.status == TransferStatus.downloading)
                  IconButton(
                    icon: Icon(Icons.pause_circle_outline_rounded,
                        color: colors.textSecondary, size: 22),
                    onPressed: onPause,
                  )
                else if (task.status == TransferStatus.paused)
                  IconButton(
                    icon: Icon(Icons.play_circle_outline_rounded,
                        color: colors.accentPrimary, size: 22),
                    onPressed: onResume,
                  ),
                IconButton(
                  icon: Icon(Icons.cancel_outlined,
                      color: colors.error, size: 22),
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
