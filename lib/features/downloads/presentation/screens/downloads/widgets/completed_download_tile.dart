/// File: completed_download_tile.dart
/// Description: List tile component rendering completed downloads with share and delete shortcuts.
library;

import 'package:flutter/material.dart';
import '../../../../../../core/models/download_job.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../shared/widgets/thumbnail_widget.dart';

/// Tile component representing a successfully downloaded file with action buttons.
class CompletedDownloadTile extends StatelessWidget {
  /// Associated DownloadJob.
  final DownloadJob job;

  /// Optional FileRecord metadata.
  final FileRecord? file;

  /// Tap callback to open file.
  final VoidCallback onTap;

  /// Share action callback.
  final VoidCallback onShare;

  /// Delete action callback.
  final VoidCallback onDelete;

  /// Constructs CompletedDownloadTile.
  const CompletedDownloadTile({
    super.key,
    required this.job,
    this.file,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _buildLeading(colors),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.name,
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
                    '${job.sizeMb.toStringAsFixed(1)} MB • Completed',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.share_outlined, color: colors.textSecondary),
              onPressed: onShare,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded,
                  color: colors.textSecondary),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds preview thumbnail or generic document container.
  Widget _buildLeading(AppColorsExtension colors) {
    if (file != null &&
        (file!.thumbnailFileId != null ||
            file!.isImage ||
            file!.isVideo ||
            file!.isPdf)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 44,
          height: 44,
          child: ThumbnailWidget(
            file: file!,
            width: 44,
            height: 44,
          ),
        ),
      );
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.accentPrimary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.insert_drive_file_outlined,
        color: colors.accentPrimary,
        size: 22,
      ),
    );
  }
}
