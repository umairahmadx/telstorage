import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/file_record.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/service_locator.dart';

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
    final uploadedStr = DateFormat('dd MMM yyyy, hh:mm a').format(file.uploadedAt);
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _buildFileIcon(colors),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file.formattedSize,
                      style: TextStyle(color: colors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                _buildInfoRow('Type', _getFileTypeLabel()),
                const Divider(color: Colors.white10, height: 32),
                _buildInfoRow('Location', _getLocationLabel(), icon: Icons.folder_open_rounded),
                const Divider(color: Colors.white10, height: 32),
                _buildInfoRow('Uploaded', uploadedStr),
                const Divider(color: Colors.white10, height: 32),
                _buildInfoRow('Size', file.formattedSize),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              _buildActionButton(Icons.share_outlined, onShare),
              const SizedBox(width: 12),
              _buildActionButton(Icons.file_download_outlined, onDownload),
              const SizedBox(width: 12),
              _buildActionButton(Icons.edit_outlined, onRename),
              const SizedBox(width: 12),
              _buildActionButton(Icons.delete_outline_rounded, onDelete, isDestructive: true),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
    return Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
        const Spacer(),
        if (icon != null) ...[
          Icon(icon, size: 16, color: Colors.white54),
          const SizedBox(width: 8),
        ],
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap, {bool isDestructive = false}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDestructive ? Colors.red.withAlpha(40) : Colors.white10),
          ),
          child: Icon(icon, color: isDestructive ? Colors.red : Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildFileIcon(AppColorsExtension colors) {
    Color iconColor = colors.fileVideo;
    if (file.isPdf) iconColor = colors.filePdf;
    if (file.name.endsWith('.fig')) iconColor = const Color(0xFF0F0F1D);

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: iconColor.withAlpha(file.name.endsWith('.fig') ? 255 : 40),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: file.name.endsWith('.fig') 
        ? const Icon(Icons.palette_outlined, color: Colors.purple, size: 28)
        : Text(_getFileTypeShort(), style: TextStyle(color: iconColor, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  String _getFileTypeShort() {
    if (file.isPdf) return 'PDF';
    if (file.isVideo) return 'MP4';
    if (file.isAudio) return 'MP3';
    return 'FILE';
  }

  String _getFileTypeLabel() {
    if (file.isPdf) return 'PDF Document';
    if (file.isVideo) return 'Video File';
    if (file.isImage) return 'Image File';
    if (file.isAudio) return 'Audio File';
    if (file.name.endsWith('.fig')) return 'Design File';
    return 'Binary File';
  }

  String _getLocationLabel() {
    if (file.folderId == null) return 'Root';
    final hive = ServiceLocator.instance.hive;
    final folder = hive.getFolder(file.folderId!);
    return folder?.name ?? 'Unknown';
  }
}
