import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/utils/file_reader_native.dart'
    if (dart.library.js_interop) '../../../core/utils/file_reader_stub.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/folder_record.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/responsive.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/folder_picker_dialog.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/file_category_helper.dart';

enum BrowserSortOption { name, date, size }

enum BrowserGroupOption { foldersFirst, fileCategory, none }

class BrowserScreen extends StatefulWidget {
  final String? currentFolderId;
  const BrowserScreen({super.key, this.currentFolderId});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  bool _isLoading = true;
  String _search = '';
  bool _gridView = false;
  bool _fabOpen = false;

  BrowserSortOption _sortOption = BrowserSortOption.name;
  bool _sortAscending = true;
  BrowserGroupOption _groupOption = BrowserGroupOption.foldersFirst;

  // Convenience getters via ServiceLocator
  get _hive => ServiceLocator.instance.hive;
  get _fileManager => ServiceLocator.instance.fileManager;
  get _download => ServiceLocator.instance.downloadService;
  get _upload => ServiceLocator.instance.uploadService;

  final Set<String> _selectedFileIds = {};
  final Set<String> _selectedFolderIds = {};

  bool get _isMultiSelect =>
      _selectedFileIds.isNotEmpty || _selectedFolderIds.isNotEmpty;

  void _toggleSelection(String id, bool isFolder) {
    setState(() {
      final set = isFolder ? _selectedFolderIds : _selectedFileIds;
      if (set.contains(id)) {
        set.remove(id);
      } else {
        set.add(id);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      await ServiceLocator.instance.init();
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRouter.login);
    }
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final result = await _showInputDialog('New Folder', 'Folder name', ctrl);
    if (result == null || result.isEmpty) return;
    try {
      await _fileManager.createFolder(result, parentId: widget.currentFolderId);
      setState(() {});
      _snack('Folder created', success: true);
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<String?> _showInputDialog(
      String title, String label, TextEditingController ctrl) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppTheme.success : AppTheme.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final scaffold = _buildScaffold();
    if (isMobile) return scaffold;
    return AppShell(selectedIndex: 1, child: scaffold);
  }

  Widget _buildScaffold() {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppTheme.primary),
          ),
        ),
      );
    }

    return ValueListenableBuilder<Box<FolderRecord>>(
      valueListenable: _hive.foldersListenable,
      builder: (context, _, __) {
        return ValueListenableBuilder<Box<FileRecord>>(
          valueListenable: _hive.filesListenable,
          builder: (context, _, __) {
            final rawFolders = _hive.subfolders(widget.currentFolderId);
            final rawFiles = _hive.filesInFolder(widget.currentFolderId);
            final q = _search.toLowerCase();
            final filteredFolders = q.isEmpty
                ? rawFolders
                : rawFolders
                    .where((f) => f.name.toLowerCase().contains(q))
                    .toList();
            final filteredFiles = q.isEmpty
                ? rawFiles
                : rawFiles
                    .where((f) => f.name.toLowerCase().contains(q))
                    .toList();

            // Apply sorting
            final List<FolderRecord> folders =
                List<FolderRecord>.from(filteredFolders);
            final List<FileRecord> files = List<FileRecord>.from(filteredFiles);

            if (_sortOption == BrowserSortOption.name) {
              folders.sort((a, b) => _sortAscending
                  ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
                  : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
              files.sort((a, b) => _sortAscending
                  ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
                  : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
            } else if (_sortOption == BrowserSortOption.date) {
              folders.sort((a, b) => _sortAscending
                  ? a.createdAt.compareTo(b.createdAt)
                  : b.createdAt.compareTo(a.createdAt));
              files.sort((a, b) => _sortAscending
                  ? a.uploadedAt.compareTo(b.uploadedAt)
                  : b.uploadedAt.compareTo(a.uploadedAt));
            } else if (_sortOption == BrowserSortOption.size) {
              folders.sort((a, b) => _sortAscending
                  ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
                  : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
              files.sort((a, b) => _sortAscending
                  ? a.sizeMb.compareTo(b.sizeMb)
                  : b.sizeMb.compareTo(a.sizeMb));
            }

            return PopScope(
              canPop: !_isMultiSelect,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                setState(() {
                  _selectedFileIds.clear();
                  _selectedFolderIds.clear();
                });
              },
              child: Scaffold(
                appBar: _buildAppBar(folders.length + files.length),
                body: Column(
                  children: [
                    _buildSearchBar(),
                    Expanded(
                      child: folders.isEmpty && files.isEmpty
                          ? _buildEmpty()
                          : _buildList(folders, files),
                    ),
                  ],
                ),
                floatingActionButton: _isMultiSelect ? null : _buildSpeedDial(),
              ),
            );
          },
        );
      },
    );
  }

  AppBar _buildAppBar(int count) {
    if (_isMultiSelect) {
      final totalSelected = _selectedFileIds.length + _selectedFolderIds.length;
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel selection',
          onPressed: () {
            setState(() {
              _selectedFileIds.clear();
              _selectedFolderIds.clear();
            });
          },
        ),
        title: Text('$totalSelected selected'),
        actions: [
          if (_selectedFileIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.drive_file_move_rounded),
              tooltip: 'Batch Move',
              onPressed: _batchMove,
            ),
          IconButton(
            icon: const Icon(Icons.delete_rounded, color: Colors.red),
            tooltip: 'Batch Delete',
            onPressed: _batchDelete,
          ),
        ],
      );
    }

    return AppBar(
      leading: widget.currentFolderId != null ? const BackButton() : null,
      automaticallyImplyLeading: widget.currentFolderId != null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.currentFolderId == null ? 'All Files' : 'Folder'),
          if (count > 0)
            Text('$count items', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        PopupMenuButton<BrowserSortOption>(
          icon: const Icon(Icons.sort_rounded),
          tooltip: 'Sort by',
          onSelected: (BrowserSortOption opt) {
            if (_sortOption == opt) {
              setState(() => _sortAscending = !_sortAscending);
            } else {
              setState(() {
                _sortOption = opt;
                _sortAscending = true;
              });
            }
          },
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              checked: _sortOption == BrowserSortOption.name,
              value: BrowserSortOption.name,
              child: Row(
                children: [
                  const Text('Name'),
                  if (_sortOption == BrowserSortOption.name) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _sortAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 14,
                    ),
                  ],
                ],
              ),
            ),
            CheckedPopupMenuItem(
              checked: _sortOption == BrowserSortOption.date,
              value: BrowserSortOption.date,
              child: Row(
                children: [
                  const Text('Date'),
                  if (_sortOption == BrowserSortOption.date) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _sortAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 14,
                    ),
                  ],
                ],
              ),
            ),
            CheckedPopupMenuItem(
              checked: _sortOption == BrowserSortOption.size,
              value: BrowserSortOption.size,
              child: Row(
                children: [
                  const Text('Size'),
                  if (_sortOption == BrowserSortOption.size) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _sortAscending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 14,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        PopupMenuButton<BrowserGroupOption>(
          icon: const Icon(Icons.group_work_rounded),
          tooltip: 'Group by',
          onSelected: (BrowserGroupOption opt) {
            setState(() => _groupOption = opt);
          },
          itemBuilder: (context) => [
            CheckedPopupMenuItem(
              checked: _groupOption == BrowserGroupOption.foldersFirst,
              value: BrowserGroupOption.foldersFirst,
              child: const Text('Folders First'),
            ),
            CheckedPopupMenuItem(
              checked: _groupOption == BrowserGroupOption.fileCategory,
              value: BrowserGroupOption.fileCategory,
              child: const Text('File Category'),
            ),
            CheckedPopupMenuItem(
              checked: _groupOption == BrowserGroupOption.none,
              value: BrowserGroupOption.none,
              child: const Text('None'),
            ),
          ],
        ),
        IconButton(
          icon: Icon(_gridView ? Icons.list_rounded : Icons.grid_view_rounded),
          tooltip: _gridView ? 'List view' : 'Grid view',
          onPressed: () => setState(() => _gridView = !_gridView),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search files and folders…',
          hintStyle: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: Icon(Icons.search_rounded,
              size: 20, color: isDark ? Colors.white38 : Colors.black38),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _search = ''),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
                color: isDark
                    ? AppTheme.darkCardBorder
                    : AppTheme.lightCardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
                color: isDark
                    ? AppTheme.darkCardBorder
                    : AppTheme.lightCardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
          ),
          filled: true,
          fillColor: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  Widget _buildEmpty() {
    final isMobile = Responsive.isMobile(context);
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppTheme.primary.withAlpha(30),
                const Color(0xFFA78BFA).withAlpha(30)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Icon(
            _search.isEmpty
                ? Icons.folder_open_rounded
                : Icons.search_off_rounded,
            size: 44,
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(height: 20),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppTheme.primary, Color(0xFFA78BFA)],
          ).createShader(bounds),
          child: Text(
            _search.isEmpty ? 'No files or folders' : 'No results found',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _search.isEmpty
              ? 'Tap + to upload files or create folders'
              : 'Try a different search term',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color),
        ),
        if (_search.isEmpty && isMobile) ...[
          const SizedBox(height: 20),
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _uploadFile,
              icon: const Icon(Icons.upload_file_rounded, size: 20),
              label: const Text('Upload File',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _buildList(List<FolderRecord> folders, List<FileRecord> files) {
    if (_gridView) return _buildGrid(folders, files);
    final isMobile = Responsive.isMobile(context);
    var animIndex = 0;

    Widget buildAnimTile(Widget tile) {
      return isMobile
          ? tile
              .animate()
              .fadeIn(duration: 300.ms, delay: (animIndex++ * 40).ms)
              .slideX(begin: 0.03, end: 0)
          : tile;
    }

    if (_groupOption == BrowserGroupOption.none) {
      final List<dynamic> combined = [...folders, ...files];
      combined.sort((a, b) {
        final nameA = a is FolderRecord ? a.name : (a as FileRecord).name;
        final nameB = b is FolderRecord ? b.name : (b as FileRecord).name;
        final dateA =
            a is FolderRecord ? a.createdAt : (a as FileRecord).uploadedAt;
        final dateB =
            b is FolderRecord ? b.createdAt : (b as FileRecord).uploadedAt;
        final sizeA = a is FolderRecord ? 0.0 : (a as FileRecord).sizeMb;
        final sizeB = b is FolderRecord ? 0.0 : (b as FileRecord).sizeMb;

        if (_sortOption == BrowserSortOption.name) {
          return _sortAscending
              ? nameA.toLowerCase().compareTo(nameB.toLowerCase())
              : nameB.toLowerCase().compareTo(nameA.toLowerCase());
        } else if (_sortOption == BrowserSortOption.date) {
          return _sortAscending
              ? dateA.compareTo(dateB)
              : dateB.compareTo(dateA);
        } else {
          return _sortAscending
              ? sizeA.compareTo(sizeB)
              : sizeB.compareTo(sizeA);
        }
      });

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _sectionLabel('All Items (${combined.length})'),
          ...combined.map((item) {
            if (item is FolderRecord) {
              return buildAnimTile(_FolderTile(
                folder: item,
                isSelected: _selectedFolderIds.contains(item.id),
                isMultiSelect: _isMultiSelect,
                onTap: () {
                  if (_isMultiSelect) {
                    _toggleSelection(item.id, true);
                  } else {
                    Navigator.of(context)
                        .pushNamed(AppRouter.browser, arguments: item.id);
                  }
                },
                onLongPress: () => _toggleSelection(item.id, true),
                onRename: () => _renameFolder(item),
                onDelete: () => _deleteFolder(item),
              ));
            } else {
              final f = item as FileRecord;
              return buildAnimTile(_FileTile(
                file: f,
                isSelected: _selectedFileIds.contains(f.fileId),
                isMultiSelect: _isMultiSelect,
                onTap: () {
                  if (_isMultiSelect) {
                    _toggleSelection(f.fileId, false);
                  } else {
                    _downloadAndView(f);
                  }
                },
                onLongPress: () => _toggleSelection(f.fileId, false),
                onRename: () => _renameFile(f),
                onDelete: () => _deleteFile(f),
                onMove: () => _moveFile(f),
              ));
            }
          }),
        ],
      );
    }

    if (_groupOption == BrowserGroupOption.fileCategory) {
      final List<FileRecord> videos = [];
      final List<FileRecord> photos = [];
      final List<FileRecord> zips = [];
      final List<FileRecord> audios = [];
      final List<FileRecord> docs = [];
      final List<FileRecord> others = [];

      for (final f in files) {
        final sub = getSubfolderForExtension(f.name);
        if (sub == 'video') {
          videos.add(f);
        } else if (sub == 'photo') {
          photos.add(f);
        } else if (sub == 'zip') {
          zips.add(f);
        } else if (sub == 'audio') {
          audios.add(f);
        } else if (sub == 'documents') {
          docs.add(f);
        } else {
          others.add(f);
        }
      }

      final List<Widget> children = [];

      void addCategorySection(
          String title, List<dynamic> items, bool isFolder) {
        if (items.isEmpty) return;
        children.add(_sectionLabel('$title (${items.length})'));
        children.addAll(items.map((item) {
          if (isFolder) {
            final f = item as FolderRecord;
            return buildAnimTile(_FolderTile(
              folder: f,
              isSelected: _selectedFolderIds.contains(f.id),
              isMultiSelect: _isMultiSelect,
              onTap: () {
                if (_isMultiSelect) {
                  _toggleSelection(f.id, true);
                } else {
                  Navigator.of(context)
                      .pushNamed(AppRouter.browser, arguments: f.id);
                }
              },
              onLongPress: () => _toggleSelection(f.id, true),
              onRename: () => _renameFolder(f),
              onDelete: () => _deleteFolder(f),
            ));
          } else {
            final f = item as FileRecord;
            return buildAnimTile(_FileTile(
              file: f,
              isSelected: _selectedFileIds.contains(f.fileId),
              isMultiSelect: _isMultiSelect,
              onTap: () {
                if (_isMultiSelect) {
                  _toggleSelection(f.fileId, false);
                } else {
                  _downloadAndView(f);
                }
              },
              onLongPress: () => _toggleSelection(f.fileId, false),
              onRename: () => _renameFile(f),
              onDelete: () => _deleteFile(f),
              onMove: () => _moveFile(f),
            ));
          }
        }));
        children.add(const SizedBox(height: 16));
      }

      addCategorySection('Folders', folders, true);
      addCategorySection('Videos', videos, false);
      addCategorySection('Photos', photos, false);
      addCategorySection('Zips', zips, false);
      addCategorySection('Audio', audios, false);
      addCategorySection('Documents', docs, false);
      addCategorySection('Others', others, false);

      if (children.isNotEmpty && children.last is SizedBox) {
        children.removeLast();
      }

      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: children,
      );
    }

    // Default: folders first
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        if (folders.isNotEmpty) ...[
          _sectionLabel('Folders (${folders.length})'),
          ...folders.map((f) {
            final tile = _FolderTile(
              folder: f,
              isSelected: _selectedFolderIds.contains(f.id),
              isMultiSelect: _isMultiSelect,
              onTap: () {
                if (_isMultiSelect) {
                  _toggleSelection(f.id, true);
                } else {
                  Navigator.of(context)
                      .pushNamed(AppRouter.browser, arguments: f.id);
                }
              },
              onLongPress: () => _toggleSelection(f.id, true),
              onRename: () => _renameFolder(f),
              onDelete: () => _deleteFolder(f),
            );
            return buildAnimTile(tile);
          }),
          const SizedBox(height: 16),
        ],
        if (files.isNotEmpty) ...[
          _sectionLabel('Files (${files.length})'),
          ...files.map((f) {
            final tile = _FileTile(
              file: f,
              isSelected: _selectedFileIds.contains(f.fileId),
              isMultiSelect: _isMultiSelect,
              onTap: () {
                if (_isMultiSelect) {
                  _toggleSelection(f.fileId, false);
                } else {
                  _downloadAndView(f);
                }
              },
              onLongPress: () => _toggleSelection(f.fileId, false),
              onRename: () => _renameFile(f),
              onDelete: () => _deleteFile(f),
              onMove: () => _moveFile(f),
            );
            return buildAnimTile(tile);
          }),
        ],
      ],
    );
  }

  Widget _buildGrid(List<FolderRecord> folders, List<FileRecord> files) {
    final isMobile = Responsive.isMobile(context);
    final cols = isMobile ? 3 : 5;

    if (_groupOption == BrowserGroupOption.none) {
      final List<dynamic> combined = [...folders, ...files];
      combined.sort((a, b) {
        final nameA = a is FolderRecord ? a.name : (a as FileRecord).name;
        final nameB = b is FolderRecord ? b.name : (b as FileRecord).name;
        final dateA =
            a is FolderRecord ? a.createdAt : (a as FileRecord).uploadedAt;
        final dateB =
            b is FolderRecord ? b.createdAt : (b as FileRecord).uploadedAt;
        final sizeA = a is FolderRecord ? 0.0 : (a as FileRecord).sizeMb;
        final sizeB = b is FolderRecord ? 0.0 : (b as FileRecord).sizeMb;

        if (_sortOption == BrowserSortOption.name) {
          return _sortAscending
              ? nameA.toLowerCase().compareTo(nameB.toLowerCase())
              : nameB.toLowerCase().compareTo(nameA.toLowerCase());
        } else if (_sortOption == BrowserSortOption.date) {
          return _sortAscending
              ? dateA.compareTo(dateB)
              : dateB.compareTo(dateA);
        } else {
          return _sortAscending
              ? sizeA.compareTo(sizeB)
              : sizeB.compareTo(sizeA);
        }
      });

      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.9,
        ),
        itemCount: combined.length,
        itemBuilder: (ctx, i) {
          final item = combined[i];
          if (item is FolderRecord) {
            final isSelected = _selectedFolderIds.contains(item.id);
            return _GridFolderItem(
              folder: item,
              isSelected: isSelected,
              isMultiSelect: _isMultiSelect,
              onTap: () {
                if (_isMultiSelect) {
                  _toggleSelection(item.id, true);
                } else {
                  Navigator.of(context)
                      .pushNamed(AppRouter.browser, arguments: item.id);
                }
              },
              onLongPress: () => _toggleSelection(item.id, true),
              onRename: () => _renameFolder(item),
              onDelete: () => _deleteFolder(item),
            );
          } else {
            final f = item as FileRecord;
            final isSelected = _selectedFileIds.contains(f.fileId);
            return _GridFileItem(
              file: f,
              isSelected: isSelected,
              isMultiSelect: _isMultiSelect,
              onTap: () {
                if (_isMultiSelect) {
                  _toggleSelection(f.fileId, false);
                } else {
                  _downloadAndView(f);
                }
              },
              onLongPress: () => _toggleSelection(f.fileId, false),
              onRename: () => _renameFile(f),
              onDelete: () => _deleteFile(f),
              onMove: () => _moveFile(f),
            );
          }
        },
      );
    }

    if (_groupOption == BrowserGroupOption.fileCategory) {
      final List<FileRecord> videos = [];
      final List<FileRecord> photos = [];
      final List<FileRecord> zips = [];
      final List<FileRecord> audios = [];
      final List<FileRecord> docs = [];
      final List<FileRecord> others = [];

      for (final f in files) {
        final sub = getSubfolderForExtension(f.name);
        if (sub == 'video') {
          videos.add(f);
        } else if (sub == 'photo') {
          photos.add(f);
        } else if (sub == 'zip') {
          zips.add(f);
        } else if (sub == 'audio') {
          audios.add(f);
        } else if (sub == 'documents') {
          docs.add(f);
        } else {
          others.add(f);
        }
      }

      final List<Widget> slivers = [];

      void addCategoryGrid(String title, List<dynamic> items, bool isFolder) {
        if (items.isEmpty) return;
        slivers.add(SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: _sectionLabel('$title (${items.length})'),
          ),
        ));
        slivers.add(SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.9,
          ),
          delegate: SliverChildBuilderDelegate(
            (ctx, idx) {
              final item = items[idx];
              if (isFolder) {
                final f = item as FolderRecord;
                final isSelected = _selectedFolderIds.contains(f.id);
                return _GridFolderItem(
                  folder: f,
                  isSelected: isSelected,
                  isMultiSelect: _isMultiSelect,
                  onTap: () {
                    if (_isMultiSelect) {
                      _toggleSelection(f.id, true);
                    } else {
                      Navigator.of(context)
                          .pushNamed(AppRouter.browser, arguments: f.id);
                    }
                  },
                  onLongPress: () => _toggleSelection(f.id, true),
                  onRename: () => _renameFolder(f),
                  onDelete: () => _deleteFolder(f),
                );
              } else {
                final f = item as FileRecord;
                final isSelected = _selectedFileIds.contains(f.fileId);
                return _GridFileItem(
                  file: f,
                  isSelected: isSelected,
                  isMultiSelect: _isMultiSelect,
                  onTap: () {
                    if (_isMultiSelect) {
                      _toggleSelection(f.fileId, false);
                    } else {
                      _downloadAndView(f);
                    }
                  },
                  onLongPress: () => _toggleSelection(f.fileId, false),
                  onRename: () => _renameFile(f),
                  onDelete: () => _deleteFile(f),
                  onMove: () => _moveFile(f),
                );
              }
            },
            childCount: items.length,
          ),
        ));
      }

      addCategoryGrid('Folders', folders, true);
      addCategoryGrid('Videos', videos, false);
      addCategoryGrid('Photos', photos, false);
      addCategoryGrid('Zips', zips, false);
      addCategoryGrid('Audio', audios, false);
      addCategoryGrid('Documents', docs, false);
      addCategoryGrid('Others', others, false);

      slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 100)));

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: CustomScrollView(
          slivers: slivers,
        ),
      );
    }

    // Default: folders first
    final List<Widget> slivers = [];
    if (folders.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: _sectionLabel('Folders (${folders.length})'),
        ),
      ));
      slivers.add(SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.9,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, idx) {
            final f = folders[idx];
            final isSelected = _selectedFolderIds.contains(f.id);
            return _GridFolderItem(
              folder: f,
              isSelected: isSelected,
              isMultiSelect: _isMultiSelect,
              onTap: () {
                if (_isMultiSelect) {
                  _toggleSelection(f.id, true);
                } else {
                  Navigator.of(context)
                      .pushNamed(AppRouter.browser, arguments: f.id);
                }
              },
              onLongPress: () => _toggleSelection(f.id, true),
              onRename: () => _renameFolder(f),
              onDelete: () => _deleteFolder(f),
            );
          },
          childCount: folders.length,
        ),
      ));
    }

    if (files.isNotEmpty) {
      slivers.add(SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: _sectionLabel('Files (${files.length})'),
        ),
      ));
      slivers.add(SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.9,
        ),
        delegate: SliverChildBuilderDelegate(
          (ctx, idx) {
            final f = files[idx];
            final isSelected = _selectedFileIds.contains(f.fileId);
            return _GridFileItem(
              file: f,
              isSelected: isSelected,
              isMultiSelect: _isMultiSelect,
              onTap: () {
                if (_isMultiSelect) {
                  _toggleSelection(f.fileId, false);
                } else {
                  _downloadAndView(f);
                }
              },
              onLongPress: () => _toggleSelection(f.fileId, false),
              onRename: () => _renameFile(f),
              onDelete: () => _deleteFile(f),
              onMove: () => _moveFile(f),
            );
          },
          childCount: files.length,
        ),
      ));
    }

    slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 100)));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CustomScrollView(
        slivers: slivers,
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4, left: 2),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
                letterSpacing: 1.1)),
      );

  Future<void> _renameFolder(FolderRecord folder) async {
    final ctrl = TextEditingController(text: folder.name);
    final result = await _showInputDialog('Rename Folder', 'New name', ctrl);
    if (result == null || result.isEmpty) return;
    try {
      await _fileManager.renameFolder(folder.id, result);
      setState(() {});
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _deleteFolder(FolderRecord folder) async {
    final ok =
        await _confirm('Delete "${folder.name}"?', 'This cannot be undone.');
    if (!ok) return;
    try {
      await _fileManager.deleteFolder(folder.id);
      setState(() {});
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _renameFile(FileRecord file) async {
    final ctrl = TextEditingController(text: file.name);
    final result = await _showInputDialog('Rename File', 'New name', ctrl);
    if (result == null || result.isEmpty) return;
    try {
      await _fileManager.renameFile(file.fileId, result);
      setState(() {});
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _deleteFile(FileRecord file) async {
    final ok =
        await _confirm('Delete "${file.name}"?', 'This cannot be undone.');
    if (!ok) return;
    try {
      await _fileManager.deleteFile(file.fileId);
      setState(() {});
      _snack('File deleted', success: true);
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<void> _moveFile(FileRecord file) async {
    final newFolderId = await showFolderPicker(
      context,
      currentFolderId: file.folderId,
      title: 'Move "${file.name}" to…',
    );
    // showFolderPicker returns null both for "Root" and "dismissed" —
    // only act if the user actually made a selection (sheet returned).
    // We can't distinguish dismiss vs root in this implementation,
    // so we always apply.
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Moving file…'),
          ],
        ),
      ),
    );

    try {
      await _fileManager.moveFile(file.fileId, newFolderId);
      if (mounted) Navigator.pop(context);
      setState(() {});
      _snack('Moved to ${newFolderId == null ? "root" : "folder"}',
          success: true);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Error moving file: $e');
    }
  }

  Future<void> _batchDelete() async {
    final totalCount = _selectedFileIds.length + _selectedFolderIds.length;
    if (totalCount == 0) return;

    final ok =
        await _confirm('Delete $totalCount items?', 'This cannot be undone.');
    if (!ok) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Deleting selected items…'),
          ],
        ),
      ),
    );

    try {
      for (final folderId in List.from(_selectedFolderIds)) {
        try {
          await _fileManager.deleteFolder(folderId);
        } catch (e) {
          AppLogger.w('Failed to delete folder $folderId: $e');
        }
      }

      for (final fileId in List.from(_selectedFileIds)) {
        await _fileManager.deleteFile(fileId);
      }

      if (mounted) Navigator.pop(context);
      _snack('$totalCount items deleted', success: true);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Error deleting items: $e');
    } finally {
      setState(() {
        _selectedFileIds.clear();
        _selectedFolderIds.clear();
      });
    }
  }

  Future<void> _batchMove() async {
    if (_selectedFileIds.isEmpty) {
      _snack('No files selected to move');
      return;
    }

    final newFolderId = await showFolderPicker(
      context,
      currentFolderId: widget.currentFolderId,
      title: 'Move ${_selectedFileIds.length} files to…',
    );

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Moving files…'),
          ],
        ),
      ),
    );

    try {
      for (final fileId in List.from(_selectedFileIds)) {
        await _fileManager.moveFile(fileId, newFolderId);
      }

      if (mounted) Navigator.pop(context);
      _snack('Moved files to ${newFolderId == null ? "root" : "folder"}',
          success: true);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _snack('Error moving files: $e');
    } finally {
      setState(() {
        _selectedFileIds.clear();
        _selectedFolderIds.clear();
      });
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _downloadAndView(FileRecord file) async {
    if (kIsWeb) {
      final notifier = ValueNotifier<({double progress, String status})>(
          (progress: 0.0, status: 'Starting…'));
      var dialogOpen = true;

      _showProgressDialog(file.name, notifier, () => dialogOpen = false);

      try {
        final bytes = await _download.downloadFile(file, (p, s) {
          notifier.value = (progress: p, status: s);
        });

        if (dialogOpen && mounted) {
          Navigator.pop(context);
          dialogOpen = false;
        }

        await _download.saveFile(bytes, file.name);
        _snack('✅ ${file.name} — download started!', success: true);
      } catch (e) {
        if (dialogOpen && mounted) Navigator.pop(context);
        _snack('❌ Download failed: $e');
      } finally {
        notifier.dispose();
      }
      return;
    }

    // Native: check file size (19 MB limit)
    if (file.sizeMb <= 19.0) {
      final notifier = ValueNotifier<({double progress, String status})>(
          (progress: 0.0, status: 'Starting…'));
      var dialogOpen = true;

      _showProgressDialog(file.name, notifier, () => dialogOpen = false);

      try {
        final bytes = await _download.downloadFile(file, (p, s) {
          notifier.value = (progress: p, status: s);
        });

        notifier.value = (progress: 0.95, status: 'Saving file…');

        final saveResult = await _download.saveAndOpen(bytes, file.name);

        if (dialogOpen && mounted) {
          Navigator.pop(context);
          dialogOpen = false;
        }

        if (saveResult.success) {
          await ServiceLocator.instance.downloadQueue
              .addCompletedJob(file, saveResult.savedPath);
          _snack('✅ Saved to downloads: ${file.name}', success: true);
        } else {
          _snack('❌ Save failed: ${saveResult.message}');
        }
      } catch (e) {
        if (dialogOpen && mounted) {
          Navigator.pop(context);
          dialogOpen = false;
        }
        _snack('❌ Download failed: $e');
      } finally {
        notifier.dispose();
      }
    } else {
      // Large file: prompt to add to background download queue
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Download Large File'),
          content: Text(
              '"${file.name}" is a large file (${file.formattedSize}). '
              'Would you like to add it to the background downloads queue?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Download in Background',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        await ServiceLocator.instance.downloadQueue.enqueueDownload(file);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${file.name}" added to download queue'),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                final shell = MobileShell.of(context);
                if (shell != null) {
                  shell.switchTab(2); // Downloads tab is index 2
                } else {
                  Navigator.of(context).pushNamed(AppRouter.downloads);
                }
              },
            ),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          ),
        );
      }
    }
  }

  void _showProgressDialog(
      String name,
      ValueNotifier<({double progress, String status})> notifier,
      VoidCallback onClosed) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder(
        valueListenable: notifier,
        builder: (context, state, __) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress == 0 ? null : state.progress,
                minHeight: 6,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            const SizedBox(height: 12),
            Text(state.status, style: Theme.of(context).textTheme.bodySmall),
            if (state.progress > 0) ...[
              const SizedBox(height: 4),
              Text('${(state.progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      color: AppTheme.primary, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    ).then((_) => onClosed());
  }

  // ── Speed Dial FAB ─────────────────────────────────────────────────────────

  Widget _buildSpeedDial() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabOpen) ...[
          _MiniAction(
            icon: Icons.upload_file_rounded,
            label: 'Upload File',
            color: const Color(0xFF10B981),
            onTap: () {
              setState(() => _fabOpen = false);
              _uploadFile();
            },
          ),
          const SizedBox(height: 8),
          _MiniAction(
            icon: Icons.create_new_folder_rounded,
            label: 'New Folder',
            color: const Color(0xFFF59E0B),
            onTap: () {
              setState(() => _fabOpen = false);
              _createFolder();
            },
          ),
          const SizedBox(height: 8),
        ],
        FloatingActionButton(
          onPressed: () => setState(() => _fabOpen = !_fabOpen),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 200),
            turns: _fabOpen ? 0.125 : 0,
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        ),
      ],
    );
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null && picked.path == null) {
      _snack('Could not read file');
      return;
    }

    final notifier = ValueNotifier<({double progress, String status})>(
        (progress: 0.0, status: 'Preparing…'));
    var dialogOpen = true;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder(
        valueListenable: notifier,
        builder: (_, state, __) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Uploading ${picked.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress == 0 ? null : state.progress,
                minHeight: 6,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              ),
            ),
            const SizedBox(height: 12),
            Text(state.status, style: Theme.of(context).textTheme.bodySmall),
            if (state.progress > 0) ...[
              const SizedBox(height: 4),
              Text('${(state.progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      color: Color(0xFF10B981), fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    ).then((_) => dialogOpen = false);

    void closeDialog() {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.pop(context);
      }
    }

    try {
      final Uint8List bytes;
      if (picked.bytes != null) {
        bytes = picked.bytes!;
      } else if (!kIsWeb && picked.path != null) {
        bytes = await _readNativeFile(picked.path!);
      } else {
        _snack('Cannot read file on this platform');
        return;
      }
      await _upload.uploadFile(
        bytes,
        picked.name,
        widget.currentFolderId,
        (p, s) => notifier.value = (progress: p, status: s),
      );
      closeDialog();
      if (!mounted) return;
      setState(() {});
      _snack('✅ ${picked.name} uploaded!', success: true);
    } catch (e) {
      closeDialog();
      if (!mounted) return;
      _snack('❌ Upload failed: $e');
    } finally {
      notifier.dispose();
    }
  }

  /// Read file bytes from native path — only call when kIsWeb == false.
  Future<Uint8List> _readNativeFile(String path) => readFileBytes(path);
}

// ── Mini FAB action button ───────────────────────────────────────────────────

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 4,
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          elevation: 4,
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tile Widgets ──────────────────────────────────────────────────────────────

class _FileTile extends StatelessWidget {
  final FileRecord file;
  final VoidCallback onTap, onRename, onDelete;
  final VoidCallback? onMove;
  final bool isSelected;
  final bool isMultiSelect;
  final VoidCallback onLongPress;

  const _FileTile({
    required this.file,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.onMove,
    required this.isSelected,
    required this.isMultiSelect,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primary.withAlpha(isDark ? 30 : 20)
            : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? AppTheme.primary
              : (isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: isMultiSelect
            ? Checkbox(
                value: isSelected,
                onChanged: (v) => onTap(),
                activeColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              )
            : Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _color().withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon(), color: _color(), size: 22),
              ),
        title: Text(file.name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge),
        subtitle: Text('${file.formattedSize} · ${_date(file.uploadedAt)}',
            style: Theme.of(context).textTheme.bodySmall),
        trailing: isMultiSelect
            ? null
            : PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  if (v == 'rename') {
                    onRename();
                  } else if (v == 'delete') {
                    onDelete();
                  } else if (v == 'move') {
                    onMove?.call();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'rename',
                      child: Row(children: [
                        Icon(Icons.edit_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Rename')
                      ])),
                  const PopupMenuItem(
                      value: 'move',
                      child: Row(children: [
                        Icon(Icons.drive_file_move_rounded,
                            size: 18, color: Color(0xFF6C63FF)),
                        SizedBox(width: 10),
                        Text('Move to folder')
                      ])),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                        SizedBox(width: 10),
                        Text('Delete', style: TextStyle(color: Colors.red))
                      ])),
                ],
              ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  IconData _icon() {
    if (file.isImage) return Icons.image_rounded;
    if (file.isVideo) return Icons.video_file_rounded;
    if (file.isAudio) return Icons.audio_file_rounded;
    if (file.isPdf) return Icons.picture_as_pdf_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _color() {
    if (file.isImage) return const Color(0xFF3B82F6);
    if (file.isVideo) return const Color(0xFFA855F7);
    if (file.isAudio) return const Color(0xFFF59E0B);
    if (file.isPdf) return const Color(0xFFEF4444);
    return AppTheme.primary;
  }

  String _date(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _FolderTile extends StatelessWidget {
  final FolderRecord folder;
  final VoidCallback onTap, onRename, onDelete;
  final bool isSelected;
  final bool isMultiSelect;
  final VoidCallback onLongPress;

  const _FolderTile({
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.isSelected,
    required this.isMultiSelect,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primary.withAlpha(isDark ? 30 : 20)
            : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? AppTheme.primary
              : (isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: isMultiSelect
            ? Checkbox(
                value: isSelected,
                onChanged: (v) => onTap(),
                activeColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
              )
            : Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_rounded,
                    color: Color(0xFFF59E0B), size: 24),
              ),
        title: Text(folder.name, style: Theme.of(context).textTheme.labelLarge),
        trailing: isMultiSelect
            ? null
            : PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                onSelected: (v) {
                  if (v == 'rename') {
                    onRename();
                  } else if (v == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'rename',
                      child: Row(children: [
                        Icon(Icons.edit_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Rename')
                      ])),
                  const PopupMenuItem(
                      value: 'delete',
                      child: Row(children: [
                        Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                        SizedBox(width: 10),
                        Text('Delete', style: TextStyle(color: Colors.red))
                      ])),
                ],
              ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}

class _GridFileItem extends StatelessWidget {
  final FileRecord file;
  final VoidCallback onTap, onRename, onDelete;
  final VoidCallback? onMove;
  final bool isSelected;
  final bool isMultiSelect;
  final VoidCallback onLongPress;

  const _GridFileItem({
    required this.file,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    this.onMove,
    required this.isSelected,
    required this.isMultiSelect,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final itemWidget = Container(
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primary.withAlpha(isDark ? 30 : 20)
            : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? AppTheme.primary
              : (isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Column(children: [
        Expanded(
            child: Center(child: Icon(_icon(), size: 40, color: _color()))),
        Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(file.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );

    return GestureDetector(
      onTap: onTap,
      onLongPress: isMultiSelect ? onTap : onLongPress,
      child: isMultiSelect
          ? Stack(
              children: [
                itemWidget,
                Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected ? AppTheme.primary : Colors.grey,
                    size: 20,
                  ),
                ),
              ],
            )
          : itemWidget,
    );
  }

  IconData _icon() {
    if (file.isImage) return Icons.image_rounded;
    if (file.isVideo) return Icons.video_file_rounded;
    if (file.isAudio) return Icons.audio_file_rounded;
    if (file.isPdf) return Icons.picture_as_pdf_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _color() {
    if (file.isImage) return const Color(0xFF3B82F6);
    if (file.isVideo) return const Color(0xFFA855F7);
    if (file.isAudio) return const Color(0xFFF59E0B);
    if (file.isPdf) return const Color(0xFFEF4444);
    return AppTheme.primary;
  }
}

class _GridFolderItem extends StatelessWidget {
  final FolderRecord folder;
  final VoidCallback onTap, onRename, onDelete;
  final bool isSelected;
  final bool isMultiSelect;
  final VoidCallback onLongPress;

  const _GridFolderItem({
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.isSelected,
    required this.isMultiSelect,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final itemWidget = Container(
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.primary.withAlpha(isDark ? 30 : 20)
            : (isDark ? AppTheme.darkCard : AppTheme.lightCard),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? AppTheme.primary
              : (isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: Column(children: [
        const Expanded(
            child: Center(
                child: Icon(Icons.folder_rounded,
                    size: 40, color: Color(0xFFF59E0B)))),
        Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(folder.name,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );

    return GestureDetector(
      onTap: onTap,
      onLongPress: isMultiSelect ? onTap : onLongPress,
      child: isMultiSelect
          ? Stack(
              children: [
                itemWidget,
                Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected ? AppTheme.primary : Colors.grey,
                    size: 20,
                  ),
                ),
              ],
            )
          : GestureDetector(
              onTap: onTap,
              onLongPress: () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                        leading: const Icon(Icons.edit_rounded),
                        title: const Text('Rename'),
                        onTap: () {
                          Navigator.pop(context);
                          onRename();
                        },
                      ),
                      ListTile(
                        leading:
                            const Icon(Icons.delete_rounded, color: Colors.red),
                        title: const Text('Delete',
                            style: TextStyle(color: Colors.red)),
                        onTap: () {
                          Navigator.pop(context);
                          onDelete();
                        },
                      ),
                    ]),
                  ),
                );
              },
              child: itemWidget,
            ),
    );
  }
}
