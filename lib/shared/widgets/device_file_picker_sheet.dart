/*
 * File: device_file_picker_sheet.dart
 * Description: In-app device storage file browser modal supporting zero-copy direct file selection for massive uploads.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/storage_permission_helper.dart';

/// Modal bottom sheet for browsing local device storage and picking files directly
/// without intermediate cache copying.
class DeviceFilePickerSheet extends StatefulWidget {
  /// Initial directory to browse (defaults to common storage root).
  final String? initialDirectory;

  /// Constructs DeviceFilePickerSheet.
  const DeviceFilePickerSheet({
    super.key,
    this.initialDirectory,
  });

  /// Displays the device file picker sheet and returns the list of selected files.
  static Future<List<File>?> show(BuildContext context) async {
    final hasPerm = await StoragePermissionHelper.ensureStoragePermission(context);
    if (!hasPerm || !context.mounted) return null;

    return showModalBottomSheet<List<File>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const DeviceFilePickerSheet(),
    );
  }

  @override
  State<DeviceFilePickerSheet> createState() => _DeviceFilePickerSheetState();
}

class _DeviceFilePickerSheetState extends State<DeviceFilePickerSheet> {
  late Directory _currentDir;
  final Set<String> _selectedFilePaths = {};
  List<FileSystemEntity> _entities = [];
  bool _isLoading = true;
  String? _errorMessage;

  static const String _defaultRoot = '/storage/emulated/0';

  @override
  void initState() {
    super.initState();
    final initialPath = widget.initialDirectory ?? _resolveDefaultDirectory();
    _currentDir = Directory(initialPath);
    _loadDirectory(_currentDir);
  }

  String _resolveDefaultDirectory() {
    if (Directory(_defaultRoot).existsSync()) {
      return _defaultRoot;
    }
    return Directory.current.path;
  }

  Future<void> _loadDirectory(Directory dir) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (!await dir.exists()) {
        throw FileSystemException('Directory does not exist', dir.path);
      }

      final rawList = await dir.list(followLinks: false).toList();
      
      // Sort: Directories first (A-Z), then files (A-Z)
      rawList.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });

      if (mounted) {
        setState(() {
          _currentDir = dir;
          _entities = rawList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Unable to open directory: $e';
        });
      }
    }
  }

  void _navigateTo(Directory dir) {
    _loadDirectory(dir);
  }

  void _navigateUp() {
    if (_currentDir.path == _defaultRoot) return;
    final parent = _currentDir.parent;
    if (parent.path != _currentDir.path) {
      _navigateTo(parent);
    }
  }

  void _toggleFileSelection(String path) {
    setState(() {
      if (_selectedFilePaths.contains(path)) {
        _selectedFilePaths.remove(path);
      } else {
        _selectedFilePaths.add(path);
      }
    });
  }

  int _calculateTotalSelectedBytes() {
    int total = 0;
    for (final path in _selectedFilePaths) {
      try {
        final f = File(path);
        if (f.existsSync()) total += f.lengthSync();
      } catch (_) {}
    }
    return total;
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  IconData _iconForFile(String filename) {
    final ext = p.extension(filename).toLowerCase();
    if (['.mp4', '.mkv', '.avi', '.mov', '.webm', '.flv', '.wmv'].contains(ext)) {
      return AppIcons.fileVideo;
    }
    if (['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.heic'].contains(ext)) {
      return AppIcons.fileImage;
    }
    if (ext == '.pdf') return AppIcons.filePdf;
    if (['.zip', '.rar', '.7z', '.tar', '.gz', '.001'].contains(ext)) {
      return AppIcons.fileArchive;
    }
    return AppIcons.fileGeneric;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final totalSelectedBytes = _calculateTotalSelectedBytes();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colors.borderSubtle,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Files to Upload',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        p.basename(_currentDir.path).isEmpty ? _currentDir.path : p.basename(_currentDir.path),
                        style: TextStyle(color: colors.textTertiary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_currentDir.path != _defaultRoot && _currentDir.parent.path != _currentDir.path)
                  IconButton(
                    icon: Icon(AppIcons.back, color: colors.textSecondary),
                    tooltip: 'Parent folder',
                    onPressed: _navigateUp,
                  ),
                IconButton(
                  icon: Icon(AppIcons.close, color: colors.textSecondary),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Quick folder shortcut chips
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildShortcutChip('🎬 Movies', '$_defaultRoot/Movies', colors),
                _buildShortcutChip('📥 Downloads', '$_defaultRoot/Download', colors),
                _buildShortcutChip('📸 DCIM', '$_defaultRoot/DCIM', colors),
                _buildShortcutChip('📁 Documents', '$_defaultRoot/Documents', colors),
                _buildShortcutChip('💾 Storage Root', _defaultRoot, colors),
              ],
            ),
          ),

          const Divider(height: 12),

          // Main files list
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: colors.accentPrimary))
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: colors.error),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _entities.isEmpty
                        ? Center(
                            child: Text(
                              'This folder is empty',
                              style: TextStyle(color: colors.textTertiary),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _entities.length,
                            itemBuilder: (ctx, index) {
                              final entity = _entities[index];
                              final isDir = entity is Directory;
                              final name = p.basename(entity.path);

                              if (isDir) {
                                return ListTile(
                                  leading: Icon(AppIcons.folder, color: colors.accentPrimary, size: 28),
                                  title: Text(
                                    name,
                                    style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Icon(AppIcons.chevronRight, color: colors.textTertiary, size: 18),
                                  onTap: () => _navigateTo(entity),
                                );
                              }

                              final isSelected = _selectedFilePaths.contains(entity.path);
                              int fileSize = 0;
                              try {
                                if (entity is File) fileSize = entity.lengthSync();
                              } catch (_) {}

                              return ListTile(
                                leading: Icon(
                                  _iconForFile(name),
                                  color: isSelected ? colors.accentPrimary : colors.textSecondary,
                                  size: 26,
                                ),
                                title: Text(
                                  name,
                                  style: TextStyle(
                                    color: isSelected ? colors.accentPrimary : colors.textPrimary,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _formatSize(fileSize),
                                  style: TextStyle(color: colors.textTertiary, fontSize: 12),
                                ),
                                trailing: Checkbox(
                                  value: isSelected,
                                  activeColor: colors.accentPrimary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  onChanged: (_) => _toggleFileSelection(entity.path),
                                ),
                                onTap: () => _toggleFileSelection(entity.path),
                              );
                            },
                          ),
          ),

          // Bottom upload action bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.bgPrimary,
              border: Border(top: BorderSide(color: colors.borderSubtle)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedFilePaths.isEmpty
                            ? 'No files selected'
                            : '${_selectedFilePaths.length} file${_selectedFilePaths.length == 1 ? "" : "s"} selected',
                        style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
                      ),
                      if (_selectedFilePaths.isNotEmpty)
                        Text(
                          _formatSize(totalSelectedBytes),
                          style: TextStyle(color: colors.accentPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: _selectedFilePaths.isEmpty
                      ? null
                      : () {
                          final selectedFiles = _selectedFilePaths
                              .map((filePath) => File(filePath))
                              .where((f) => f.existsSync())
                              .toList();
                          Navigator.pop(context, selectedFiles);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.accentPrimary,
                    foregroundColor: colors.bgPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Upload', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutChip(String label, String path, AppColorsExtension colors) {
    final isCurrent = _currentDir.path == path;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(
          label,
          style: TextStyle(
            color: isCurrent ? colors.bgPrimary : colors.textSecondary,
            fontSize: 12,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        backgroundColor: isCurrent ? colors.accentPrimary : colors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        side: BorderSide(color: isCurrent ? colors.accentPrimary : colors.borderSubtle),
        onPressed: () {
          final dir = Directory(path);
          if (dir.existsSync()) {
            _navigateTo(dir);
          }
        },
      ),
    );
  }
}
