import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/file_record.dart';
import '../../core/theme/app_theme.dart';
import '../../core/services/service_locator.dart';
import 'thumbnail_widget.dart';

class FileDetailSheet extends StatelessWidget {
  final FileRecord file;
  final VoidCallback onShare;
  final VoidCallback onDownload;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const FileDetailSheet({
    super.key,
    required this.file,
    required this.onShare,
    required this.onDownload,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(file.uploadedAt);

    return Container(
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: colors.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // File Header
          Row(
            children: [
              _buildIcon(colors),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${file.formattedSize} • $dateStr',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ActionButton(
                icon: Icons.share_rounded,
                label: 'Share',
                onTap: onShare,
              ),
              _ActionButton(
                icon: Icons.download_rounded,
                label: 'Download',
                onTap: onDownload,
              ),
              _ActionButton(
                icon: Icons.edit_rounded,
                label: 'Rename',
                onTap: onRename,
              ),
              _ActionButton(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                color: colors.error,
                onTap: onDelete,
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          // Details List
          _DetailRow(label: 'Type', value: file.mimeType.toUpperCase()),
          _DetailRow(label: 'Location', value: _getFolderName()),
          _DetailRow(label: 'Checksum', value: _formatHash(file.sha256Hash)),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildIcon(AppColorsExtension colors) {
    if (file.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ThumbnailWidget(
          file: file,
          width: 64,
          height: 64,
          fallback: Container(
            width: 64,
            height: 64,
            color: colors.bgSurfaceInset,
            child: Icon(Icons.image_rounded, color: colors.textTertiary),
          ),
        ),
      );
    }

    Color iconColor = colors.textPrimary;
    if (file.isPdf) iconColor = colors.filePdf;
    if (file.isVideo) iconColor = colors.fileVideo;
    if (file.name.endsWith('.zip')) iconColor = colors.fileZip;
    if (file.name.endsWith('.fig')) iconColor = colors.filePalette;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: colors.bgSurfaceInset,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        _getIconData(),
        color: iconColor,
        size: 32,
      ),
    );
  }

  IconData _getIconData() {
    if (file.isPdf) return Icons.picture_as_pdf_rounded;
    if (file.isVideo) return Icons.play_circle_fill_rounded;
    if (file.name.endsWith('.zip')) return Icons.folder_zip_rounded;
    return Icons.insert_drive_file_rounded;
  }

  String _getFolderName() {
    if (file.folderId == null) return 'Root';
    final hive = ServiceLocator.instance.hive;
    return hive.getFolder(file.folderId!)?.name ?? 'Unknown';
  }

  String _formatHash(String? hash) {
    if (hash == null || hash.isEmpty) return 'Not available';
    if (hash.length > 20) {
      return '${hash.substring(0, 10)}...${hash.substring(hash.length - 10)}';
    }
    return hash;
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final themeColor = color ?? colors.accentPrimary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: themeColor.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: themeColor, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.textTertiary, fontSize: 13),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
