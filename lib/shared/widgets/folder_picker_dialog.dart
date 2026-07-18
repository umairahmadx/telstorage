import 'package:flutter/material.dart';
import '../../core/services/service_locator.dart';
import '../../core/theme/app_theme.dart';

class FolderPickerDialog extends StatefulWidget {
  final String? currentFolderId;
  const FolderPickerDialog({super.key, this.currentFolderId});

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  String? _selectedFolderId;

  @override
  void initState() {
    super.initState();
    _selectedFolderId = widget.currentFolderId;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final folders = ServiceLocator.instance.hive.allFolders
        .where((f) => f.id != widget.currentFolderId)
        .toList();

    return AlertDialog(
      backgroundColor: colors.bgSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Move to Folder',
          style: Theme.of(context).textTheme.headlineMedium),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: folders.isEmpty
            ? Center(
                child: Text('No other folders available',
                    style: TextStyle(color: colors.textTertiary)))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: folders.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == 0) {
                    return _buildFolderTile(
                        null, 'Root Directory', _selectedFolderId == null, colors);
                  }
                  final f = folders[i - 1];
                  return _buildFolderTile(
                      f.id, f.name, _selectedFolderId == f.id, colors);
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selectedFolderId),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.accentPrimary,
            foregroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Move Here'),
        ),
      ],
    );
  }

  Widget _buildFolderTile(
      String? id, String name, bool isSelected, AppColorsExtension colors) {
    return ListTile(
      leading: Icon(Icons.folder_rounded,
          color: isSelected ? colors.accentPrimary : colors.fileFolder),
      title: Text(name,
          style: TextStyle(
            color: isSelected ? colors.textPrimary : colors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          )),
      trailing: isSelected
          ? Icon(Icons.check_circle_rounded, color: colors.accentPrimary)
          : null,
      onTap: () => setState(() => _selectedFolderId = id),
    );
  }
}
