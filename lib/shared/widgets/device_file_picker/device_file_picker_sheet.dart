/*
 * File: device_file_picker_sheet.dart
 * Description: Redesigned in-app device storage file browser modal supporting zero-copy direct file
 * selection for massive uploads, breadcrumb navigation, search filtering, and category tabs.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_colors_extension.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/utils/file_opener_helper.dart';
import '../../../../core/utils/storage_permission_helper.dart';
import 'device_file_breadcrumbs.dart';
import 'device_file_filter_tabs.dart';
import 'device_file_thumbnail.dart';
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
  late final String _rootDirectory;
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
    _rootDirectory = widget.initialDirectory ?? _resolveDefaultDirectory();
    _currentDir = Directory(initialPath);
    _loadDirectory(_currentDir);
  }

  bool get _canGoBack {
    final cur = p.normalize(_currentDir.path);
    final root = p.normalize(_rootDirectory);
    return cur != root && _currentDir.parent.path != _currentDir.path;
  }

  void _handleBack() {
    if (_canGoBack) {
      _loadDirectory(_currentDir.parent);
    } else {
      Navigator.pop(context);
    }
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
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
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
    const s = ['B', 'KB', 'MB', 'GB', 'TB'];
    var d = bytes.toDouble(), i = 0;
    while (d >= 1024 && i < s.length - 1) { d /= 1024; i++; }
    return '${d.toStringAsFixed(1)} ${s[i]}';
  }

  IconData _iconForFile(String filename) {
    final ext = p.extension(filename).toLowerCase();
    if (ext == '.pdf') return AppIcons.filePdf;
    if (const {'.mp4', '.mkv', '.mov', '.webm', '.avi'}.contains(ext)) return AppIcons.fileVideo;
    if (const {'.mp3', '.m4a', '.flac', '.wav', '.ogg', '.aac'}.contains(ext)) return AppIcons.fileAudio;
    if (const {'.jpg', '.jpeg', '.png', '.gif', '.webp'}.contains(ext)) return AppIcons.fileImage;
    if (const {'.zip', '.rar', '.7z', '.tar', '.gz'}.contains(ext)) return AppIcons.fileArchive;
    return AppIcons.fileGeneric;
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

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Container(
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
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      icon: Icon(
                        AppIcons.back,
                        color: _canGoBack
                            ? (colors?.textPrimary ?? Colors.white)
                            : (colors?.textTertiary ?? Colors.white38),
                        size: 20,
                      ),
                      tooltip: 'Previous',
                      onPressed: _handleBack,
                    ),
                  ),
                  const SizedBox(width: 8),
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
            rootPath: _rootDirectory,
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
    ),
  );
  }

  Widget _buildEntityList(
      List<FileSystemEntity> entities, AppColorsExtension? colors) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colors?.brandPrimary),
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
          leading: DeviceFileThumbnail(
            filePath: entity.path,
            fileName: name,
            icon: _iconForFile(name),
            iconColor: isSelected
                ? (colors?.brandPrimary ?? AppColors.primary)
                : (colors?.textSecondary ?? Colors.white70),
            onOpen: () =>
                FileOpenerHelper.openFile(context, filePath: entity.path),
          ),
          title: Text(
            name,
            style: TextStyle(
              color: isSelected
                  ? (colors?.brandPrimary ?? AppColors.primary)
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: colors?.textTertiary ?? Colors.white38,
                ),
                tooltip: 'Open in system default app',
                onPressed: () =>
                    FileOpenerHelper.openFile(context, filePath: entity.path),
              ),
              Checkbox(
                value: isSelected,
                activeColor: colors?.brandPrimary ?? AppColors.primary,
                checkColor: AppColors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                onChanged: (_) => _toggleFileSelection(entity.path),
              ),
            ],
          ),
          onTap: () => _toggleFileSelection(entity.path),
        );
      },
    );
  }
}
