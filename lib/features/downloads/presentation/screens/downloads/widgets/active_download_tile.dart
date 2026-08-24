/// File: active_download_tile.dart
/// Description: List tile component rendering in-progress download and upload transfers with progress bar and controls.
library;

import 'package:flutter/material.dart';
import '../../../../../../core/models/transfer_task.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/app_common_widgets.dart';

/// Tile component representing an active transfer item with pause/resume/cancel buttons.
class ActiveDownloadTile extends StatelessWidget {
  /// Associated transfer task.
  final TransferTask task;

  /// Callback when pause action is pressed.
  final VoidCallback onPause;

  /// Callback when resume action is pressed.
  final VoidCallback onResume;

  /// Callback when cancel action is pressed.
  final VoidCallback onCancel;

  /// Constructs ActiveDownloadTile.
  const ActiveDownloadTile({
    super.key,
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  task.type == TransferType.upload
                      ? Icons.cloud_upload_rounded
                      : Icons.cloud_download_rounded,
                  color: colors.accentPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.name,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(task.progress * 100).toInt()}% • ${task.currentStage}',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (task.status == TransferStatus.uploading ||
                  task.status == TransferStatus.downloading)
                IconButton(
                  icon: Icon(Icons.pause_circle_outline_rounded,
                      color: colors.textSecondary),
                  onPressed: onPause,
                )
              else if (task.status == TransferStatus.paused)
                IconButton(
                  icon: Icon(Icons.play_circle_outline_rounded,
                      color: colors.accentPrimary),
                  onPressed: onResume,
                ),
              IconButton(
                icon: Icon(Icons.cancel_outlined, color: colors.error),
                onPressed: onCancel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppProgressBar(
            value: task.progress > 0 ? task.progress : null,
            minHeight: 6,
            radius: 3,
            valueColor: colors.accentPrimary,
          ),
        ],
      ),
    );
  }
}
