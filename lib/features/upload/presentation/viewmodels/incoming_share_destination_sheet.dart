/*
 * File: incoming_share_destination_sheet.dart
 * Description: Lets users choose the TelStorage folder for files shared into the app.
 */

import 'package:flutter/material.dart';

import '../../../../core/models/folder_record.dart';

class IncomingShareDestination {
  const IncomingShareDestination(this.folderId);

  /// Null selects TelStorage's root folder.
  final String? folderId;
}

class IncomingShareDestinationSheet extends StatefulWidget {
  const IncomingShareDestinationSheet({
    required this.fileNames,
    required this.folders,
    this.onCreateFolder,
    super.key,
  });

  final List<String> fileNames;
  final List<FolderRecord> folders;

  /// Creates a folder under [parentId] (null for root) and returns its
  /// record, or null on failure. When absent, folder creation is hidden.
  final Future<FolderRecord?> Function(String name, String? parentId)?
      onCreateFolder;

  static Future<IncomingShareDestination?> show(
    BuildContext context, {
    required List<String> fileNames,
    required List<FolderRecord> folders,
    Future<FolderRecord?> Function(String name, String? parentId)?
        onCreateFolder,
  }) {
    return showModalBottomSheet<IncomingShareDestination>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => IncomingShareDestinationSheet(
        fileNames: fileNames,
        folders: folders,
        onCreateFolder: onCreateFolder,
      ),
    );
  }

  @override
  State<IncomingShareDestinationSheet> createState() =>
      _IncomingShareDestinationSheetState();
}

class _IncomingShareDestinationSheetState
    extends State<IncomingShareDestinationSheet> {
  final List<String> _folderStack = [];
  late final List<FolderRecord> _folders = List.of(widget.folders);

  String? get _currentFolderId =>
      _folderStack.isEmpty ? null : _folderStack.last;

  FolderRecord? get _currentFolder {
    final id = _currentFolderId;
    if (id == null) return null;
    for (final folder in _folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  Future<void> _promptCreateFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || !mounted) return;
    final folder = await widget.onCreateFolder!(name, _currentFolderId);
    if (!mounted) return;
    if (folder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create the folder.')),
      );
      return;
    }
    setState(() {
      _folders.add(folder);
      _folderStack.add(folder.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentFolder = _currentFolder;
    final children = _folders
        .where((folder) => folder.parentId == _currentFolderId)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upload to TelStorage',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  for (final fileName in widget.fileNames.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined,
                              size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.fileNames.length > 3)
                    Text(
                      '+${widget.fileNames.length - 3} more',
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_folderStack.isNotEmpty)
                        IconButton(
                          tooltip: 'Go up',
                          onPressed: () => setState(_folderStack.removeLast),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      Expanded(
                        child: Text(
                          currentFolder == null
                              ? 'Destination: Root folder'
                              : 'Destination: ${currentFolder.name}',
                          style: theme.textTheme.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.onCreateFolder != null)
                        IconButton(
                          tooltip: 'New folder',
                          onPressed: _promptCreateFolder,
                          icon: const Icon(Icons.create_new_folder_outlined),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: children.isEmpty
                  ? Center(
                      child: Text(
                        _currentFolderId == null
                            ? (widget.onCreateFolder == null
                                ? 'No folders yet. Upload to the root folder.'
                                : 'No folders yet. Create one or upload to the root folder.')
                            : 'This folder has no subfolders.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      itemCount: children.length,
                      itemBuilder: (context, index) {
                        final folder = children[index];
                        return ListTile(
                          leading: const Icon(Icons.folder_rounded),
                          title: Text(folder.name),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () =>
                              setState(() => _folderStack.add(folder.id)),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      IncomingShareDestination(_currentFolderId),
                    ),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: Text(
                      currentFolder == null ? 'Upload to root' : 'Upload here',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
