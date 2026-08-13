import 'package:flutter/material.dart';
import '../../../../core/models/file_record.dart';
import '../../../../core/navigation/navigation_intent.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_surface_card.dart';
import '../../../../shared/widgets/thumbnail_widget.dart';

class RecentFilesSection extends StatelessWidget {
  final List<FileRecord> files;
  final ValueChanged<FileRecord> onMore;

  const RecentFilesSection({
    super.key,
    required this.files,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Files',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            GestureDetector(
              onTap: () => ServiceLocator.instance.navigation
                  .navigateTo(AppDestination.files),
              child: Text(
                'View all',
                style: TextStyle(color: colors.textSecondary, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (files.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40.0),
              child: Text(
                'No recent files',
                style: TextStyle(color: colors.textTertiary),
              ),
            ),
          )
        else
          AppSurfaceCard(
            radius: 24,
            child: Column(
              children: List.generate(
                files.length,
                (i) => RecentFileTile(
                  file: files[i],
                  isLast: i == files.length - 1,
                  onMore: () => onMore(files[i]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class RecentFileTile extends StatelessWidget {
  final FileRecord file;
  final bool isLast;
  final VoidCallback onMore;

  const RecentFileTile({
    super.key,
    required this.file,
    required this.onMore,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _buildLeading(colors),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${file.formattedSize} • ${_formatDate(file.uploadedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_horiz_rounded, color: colors.textSecondary),
                onPressed: onMore,
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(indent: 12, endIndent: 12, color: colors.borderSubtle),
      ],
    );
  }

  Widget _buildLeading(AppColorsExtension colors) {
    final mime = file.mimeType;
    if (file.thumbnailFileId != null || file.isImage || file.isVideo || file.isPdf) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 40,
          height: 40,
          child: ThumbnailWidget(
            file: file,
            width: 40,
            height: 40,
          ),
        ),
      );
    }

    Color iconColor;
    String label = '';

    if (mime.startsWith('video/')) {
      iconColor = colors.fileVideo;
      label = 'VIDEO';
    } else if (mime == 'application/pdf') {
      iconColor = colors.filePdf;
      label = 'PDF';
    } else if (file.name.endsWith('.fig')) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.bgSurfaceInset,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child:
            Icon(Icons.palette_outlined, color: colors.filePalette, size: 20),
      );
    } else {
      iconColor = colors.fileZip;
      label = 'ZIP';
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: iconColor.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
            color: iconColor, fontSize: 9, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
