/*
 * File: downloads_active_section.dart
 * Description: Section rendering in-flight download and upload transfer tasks with progress controls.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/models/transfer_task.dart';
import '../../../../../../core/services/transfer_queue_service.dart';
import '../../../../../../shared/widgets/tiles/app_transfer_tile.dart';
import '../../../../../../shared/widgets/typography/app_section_label.dart';

/// Renders a list of active transfer tasks with pause, resume, and cancel capabilities.
class DownloadsActiveSection extends StatelessWidget {
  final List<TransferTask> activeTransfers;

  const DownloadsActiveSection({
    super.key,
    required this.activeTransfers,
  });

  @override
  Widget build(BuildContext context) {
    if (activeTransfers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSectionLabel(
          label: 'Active (${activeTransfers.length})',
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        ),
        ...activeTransfers.map(
          (task) => AppTransferTile(
            task: task,
            onPause: () => TransferQueueService.instance.pauseTask(task.id),
            onResume: () => TransferQueueService.instance.resumeTask(task.id),
            onCancel: () => TransferQueueService.instance.cancelTask(task.id),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
