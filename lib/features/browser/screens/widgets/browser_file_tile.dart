import 'package:flutter/material.dart';
import '../../../../core/models/file_record.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/thumbnail_widget.dart';

class BrowserFileTile extends StatelessWidget {
  final FileRecord file;
  final bool isSelected;
  final bool isMultiSelect;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  const BrowserFileTile({
    super.key,
    required this.file,
    this.isSelected = false,
    this.isMultiSelect = false,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: isSelected
            ? colors.accentPrimary.withValues(alpha: 0.15)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (isMultiSelect)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected
                      ? colors.accentPrimary
                      : colors.textTertiary,
                ),
              ),
            _buildLeading(colors),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
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
                    '${file.formattedSize} • ${_formatDate(file.uploadedAt)}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary),
              onPressed: onMore,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeading(AppColorsExtension colors) {
    final mime = file.mimeType;
    if (file.thumbnailFileId != null || file.isImage || file.isVideo || file.isPdf) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 44,
          height: 44,
          child: ThumbnailWidget(
            file: file,
            width: 44,
            height: 44,
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
    } else {
      iconColor = colors.fileZip;
      label = 'FILE';
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: iconColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
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
