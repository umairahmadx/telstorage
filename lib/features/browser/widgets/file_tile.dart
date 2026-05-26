import 'package:flutter/material.dart';
import '../../../core/models/file_record.dart';

class FileTile extends StatelessWidget {
  final FileRecord file;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  const FileTile({
    super.key,
    required this.file,
    required this.onTap,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getColor().withOpacity(0.1),
          child: Icon(_getIcon(), color: _getColor()),
        ),
        title: Text(file.name),
        subtitle: Text(
          '${file.formattedSize} • ${_formatDate(file.uploadedAt)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showContextMenu(context),
        ),
        onTap: onTap,
      ),
    );
  }

  IconData _getIcon() {
    if (file.isImage) return Icons.image;
    if (file.isVideo) return Icons.video_file;
    if (file.isAudio) return Icons.audio_file;
    if (file.isPdf) return Icons.picture_as_pdf;
    return Icons.insert_drive_file;
  }

  Color _getColor() {
    if (file.isImage) return Colors.blue;
    if (file.isVideo) return Colors.purple;
    if (file.isAudio) return Colors.orange;
    if (file.isPdf) return Colors.red;
    return Colors.grey;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                onRename();
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move),
              title: const Text('Move to'),
              onTap: () {
                Navigator.pop(context);
                onMove();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}
