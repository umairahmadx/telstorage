/*
 * File: downloads_completed_section.dart
 * Description: Section rendering completed download jobs with open, share, and deletion actions.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../core/models/download_job.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/tiles/app_file_tile.dart';
import '../../../../../../shared/widgets/typography/app_section_label.dart';
import '../viewmodel/downloads_view_model.dart';

/// Renders completed download entries with file opening, sharing, and removal controls.
class DownloadsCompletedSection extends StatelessWidget {
  final List<DownloadJob> completedDownloads;
  final void Function(String? localPath, {String? mimeType, String? fileName})
      onOpenFile;
  final void Function(DownloadJob job, FileRecord? file) onShareJob;
  final void Function(DownloadJob job) onDeleteJob;

  const DownloadsCompletedSection({
    super.key,
    required this.completedDownloads,
    required this.onOpenFile,
    required this.onShareJob,
    required this.onDeleteJob,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    if (completedDownloads.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSectionLabel(
          label: 'Completed Downloads (${completedDownloads.length})',
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        ),
        ...completedDownloads.map((job) {
          final file = context.read<TransferCubit>().getFile(job.fileId);
          final record = file ??
              FileRecord(
                fileId: job.fileId,
                metadataMessageId: 0,
                metadataFileId: '',
                name: job.name,
                sizeMb: job.sizeMb,
                mimeType: job.mimeType,
                uploadedAt: job.completedAt ?? DateTime.now(),
                chunkCount: 1,
                sha256Hash: '',
              );

          return AppFileTile(
            file: record,
            subtitleText: job.localPath,
            onTap: () => onOpenFile(
              job.localPath,
              mimeType: job.mimeType,
              fileName: job.name,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.share_outlined,
                      color: colors.textSecondary, size: 20),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onShareJob(job, file);
                  },
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      color: colors.error, size: 20),
                  onPressed: () => onDeleteJob(job),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
