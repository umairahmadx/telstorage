/*
 * File: file_detail_sheet.dart
 * Description: Centralized modal bottom sheet displaying full file metadata, preview, and actions for a FileRecord.
 */

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/thumbnail_widget.dart';

/// Centralized 'About File' modal bottom sheet.
class FileDetailSheet extends StatelessWidget {
  /// Associated FileRecord entity.
  final FileRecord file;

  /// Callback when Share is pressed.
  final VoidCallback onShare;

  /// Callback when Download is pressed.
  final VoidCallback onDownload;

  /// Callback when Rename is pressed.
  final VoidCallback onRename;

  /// Callback when Move is pressed.
  final VoidCallback? onMove;

  /// Callback when Copy is pressed.
  final VoidCallback? onCopy;

  /// Callback when Delete is pressed.
  final VoidCallback onDelete;

  /// Constructs FileDetailSheet.
  const FileDetailSheet({
    super.key,
    required this.file,
    required this.onShare,
    required this.onDownload,
    required this.onRename,
    this.onMove,
    this.onCopy,
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

          // File Header with Thumbnail
          Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: ThumbnailWidget(file: file, width: 56, height: 56),
              ),
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

          const SizedBox(height: 28),

          // Actions Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ActionButton(
                  icon: AppIcons.share,
                  label: 'Share',
                  onTap: onShare,
                ),
                _ActionButton(
                  icon: AppIcons.download,
                  label: 'Download',
                  onTap: onDownload,
                ),
                _ActionButton(
                  icon: AppIcons.rename,
                  label: 'Rename',
                  onTap: onRename,
                ),
                if (onMove != null)
                  _ActionButton(
                    icon: AppIcons.move,
                    label: 'Move',
                    onTap: onMove!,
                  ),
                if (onCopy != null)
                  _ActionButton(
                    icon: AppIcons.copyLink,
                    label: 'Copy',
                    onTap: onCopy!,
                  ),
                _ActionButton(
                  icon: AppIcons.delete,
                  label: 'Delete',
                  onTap: onDelete,
                  isDestructive: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          const Divider(height: 1),
          const SizedBox(height: 20),

          // Detailed Metadata List
          _DetailRow(label: 'Type', value: file.mimeType),
          _DetailRow(label: 'Size', value: file.formattedSize),
          _DetailRow(label: 'Date Uploaded', value: dateStr),
          _DetailRow(label: 'Message ID', value: file.metadataMessageId.toString()),
          if (file.sha256Hash.isNotEmpty)
            _DetailRow(label: 'SHA-256', value: file.sha256Hash),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final color = isDestructive ? colors.error : colors.textPrimary;
    final borderRadius = BorderRadius.circular(16);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: isDestructive
                      ? colors.error.withValues(alpha: 0.12)
                      : colors.bgSurfaceInset,
                  borderRadius: BorderRadius.circular(14),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Icon(icon, color: color, size: 20),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
