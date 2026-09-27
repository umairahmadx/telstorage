/*
 * File: device_file_picker_sheet.dart
 * Description: Redesigned in-app device storage file browser modal supporting zero-copy direct file
 * selection for massive uploads, breadcrumb navigation, search filtering, and category tabs.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../../core/theme/app_colors_extension.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/utils/storage_permission_helper.dart';
import 'device_file_breadcrumbs.dart';
import 'device_file_filter_tabs.dart';
import 'device_picker_bottom_bar.dart';

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
    final hasPerm =
        await StoragePermissionHelper.ensureStoragePermission(context);
    if (!hasPerm || !context.mounted) return null;

    return showModalBottomSheet<List<File>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DeviceFilePickerSheet(),
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
  String _activeFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const String _defaultRoot = '/storage/emulated/0';

  @override
  void initState() {
    super.initState();
    final initialPath = widget.initialDirectory ?? _resolveDefaultDirectory();
    _currentDir = Directory(initialPath);
    _loadDirectory(_currentDir);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

      rawList.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
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
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _navigateTo(Directory dir) {
    _loadDirectory(dir);
  }

  void _toggleFileSelection(String filePath) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedFilePaths.contains(filePath)) {
        _selectedFilePaths.remove(filePath);
      } else {
        _selectedFilePaths.add(filePath);
      }
    });
  }

  void _toggleSelectAll(List<FileSystemEntity> displayedFiles) {
    HapticFeedback.lightImpact();
    setState(() {
      final displayedFilePaths =
          displayedFiles.map((e) => e.path).toSet();
      final allDisplayedSelected =
          displayedFilePaths.every(_selectedFilePaths.contains);

      if (allDisplayedSelected) {
        _selectedFilePaths.removeAll(displayedFilePaths);
      } else {
        _selectedFilePaths.addAll(displayedFilePaths);
      }
    });
  }

  int _calculateSelectedBytes() {
    var total = 0;
    for (final path in _selectedFilePaths) {
      try {
        final f = File(path);
        if (f.existsSync()) total += f.lengthSync();
      } catch (_) {}
    }
    return total;
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  IconData _iconForFile(String filename) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.pdf':
        return AppIcons.filePdf;
      case '.mp4':
      case '.mkv':
      case '.mov':
      case '.webm':
      case '.avi':
        return AppIcons.fileVideo;
      case '.mp3':
      case '.m4a':
      case '.flac':
      case '.wav':
      case '.ogg':
      case '.aac':
        return AppIcons.fileAudio;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.webp':
        return AppIcons.fileImage;
      case '.zip':
      case '.rar':
      case '.7z':
      case '.tar':
      case '.gz':
        return AppIcons.fileArchive;
      default:
        return AppIcons.fileGeneric;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();
    final sheetHeight = MediaQuery.of(context).size.height * 0.90;

    // Filter entities
    final visibleEntities = _entities.where((e) {
      final name = p.basename(e.path);
      if (_searchQuery.isNotEmpty &&
          !name.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      if (e is File &&
          !DeviceFileFilterTabs.matchesFilter(name, _activeFilter)) {
        return false;
      }
      return true;
    }).toList();

    final visibleFiles =
        visibleEntities.whereType<File>().toList();

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: colors?.bgPrimary ?? Colors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors?.borderSubtle ?? Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: colors?.bgSurfaceInset ?? Colors.white10,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          AppIcons.search,
                          size: 16,
                          color: colors?.textSecondary ?? Colors.white54,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: TextStyle(
                              color: colors?.textPrimary ?? Colors.white,
                              fontSize: 13,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search files in folder...',
                              hintStyle: TextStyle(
                                color: colors?.textTertiary ?? Colors.white38,
                                fontSize: 13,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (val) {
                              setState(() => _searchQuery = val);
                            },
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: Icon(
                              AppIcons.close,
                              size: 14,
                              color: colors?.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    icon: Icon(AppIcons.close, color: colors?.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
          // Breadcrumb Navigation
          DeviceFileBreadcrumbs(
            currentPath: _currentDir.path,
            rootPath: _defaultRoot,
            onNavigate: (path) => _navigateTo(Directory(path)),
          ),
          const SizedBox(height: 6),
          // Category Filter Tabs
          DeviceFileFilterTabs(
            activeFilter: _activeFilter,
            onFilterChanged: (filter) {
              setState(() => _activeFilter = filter);
            },
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, thickness: 1),
          // File & Directory List
          Expanded(
            child: _buildEntityList(visibleEntities, colors),
          ),
          // Batch Action Bottom Bar
          DevicePickerBottomBar(
            selectedCount: _selectedFilePaths.length,
            totalBytes: _calculateSelectedBytes(),
            isAllSelected: visibleFiles.isNotEmpty &&
                visibleFiles.every((f) => _selectedFilePaths.contains(f.path)),
            onToggleSelectAll: () => _toggleSelectAll(visibleFiles),
            onSubmit: () {
              final selectedFiles = _selectedFilePaths
                  .map((p) => File(p))
                  .where((f) => f.existsSync())
                  .toList();
              Navigator.pop(context, selectedFiles);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEntityList(
      List<FileSystemEntity> entities, AppColorsExtension? colors) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colors?.accentPrimary),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            style: TextStyle(color: colors?.error ?? Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (entities.isEmpty) {
      return Center(
        child: Text(
          'No files found',
          style: TextStyle(color: colors?.textTertiary ?? Colors.white38),
        ),
      );
    }

    return ListView.builder(
      itemCount: entities.length,
      itemBuilder: (ctx, index) {
        final entity = entities[index];
        final isDir = entity is Directory;
        final name = p.basename(entity.path);

        if (isDir) {
          return ListTile(
            leading: Icon(
              AppIcons.folder,
              color: colors?.fileFolder ?? colors?.accentPrimary,
              size: 26,
            ),
            title: Text(
              name,
              style: TextStyle(
                color: colors?.textPrimary ?? Colors.white,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(
              AppIcons.chevronRight,
              color: colors?.textTertiary ?? Colors.white24,
              size: 18,
            ),
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
            color: isSelected
                ? (colors?.accentPrimary ?? Colors.blue)
                : (colors?.textSecondary ?? Colors.white70),
            size: 24,
          ),
          title: Text(
            name,
            style: TextStyle(
              color: isSelected
                  ? (colors?.accentPrimary ?? Colors.blue)
                  : (colors?.textPrimary ?? Colors.white),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _formatSize(fileSize),
            style: TextStyle(
              color: colors?.textTertiary ?? Colors.white38,
              fontSize: 12,
            ),
          ),
          trailing: Checkbox(
            value: isSelected,
            activeColor: colors?.accentPrimary,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            onChanged: (_) => _toggleFileSelection(entity.path),
          ),
          onTap: () => _toggleFileSelection(entity.path),
        );
      },
    );
  }
}
