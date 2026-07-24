import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/folder_record.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_icons.dart';
import '../../../shared/widgets/thumbnail_widget.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../shared/widgets/share_link_sheet.dart';
import '../../../shared/widgets/file_detail_sheet.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/app_surface_card.dart';
import '../../../core/services/service_locator.dart';
import '../../sync/screens/sync_screen.dart';
import '../bloc/browser_bloc.dart';
import '../../downloads/bloc/transfer_cubit.dart';

enum BrowserSortOption { name, date, size }

enum BrowserGroupOption { foldersFirst, fileCategory, none }

class BrowserScreen extends StatefulWidget {
  final String? currentFolderId;
  final String? category;
  const BrowserScreen({super.key, this.currentFolderId, this.category});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  @override
  void initState() {
    super.initState();
    context.read<BrowserBloc>().add(LoadDirectory(
        folderId: widget.currentFolderId, category: widget.category));
  }

  void _showFileDetail(FileRecord file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FileDetailSheet(
        file: file,
        onShare: () {
          Navigator.pop(ctx);
          _showShareSheet(file);
        },
        onDownload: () {
          Navigator.pop(ctx);
          _downloadAndView(file);
        },
        onRename: () {
          Navigator.pop(ctx);
          _renameFile(file);
        },
        onMove: () {
          Navigator.pop(ctx);
          context.read<BrowserBloc>().add(SetClipboard(
            mode: ClipboardMode.move,
            fileIds: {file.fileId},
            folderIds: {},
            sourceFolderId: file.folderId,
          ));
        },
        onCopy: () {
          Navigator.pop(ctx);
          context.read<BrowserBloc>().add(SetClipboard(
            mode: ClipboardMode.copy,
            fileIds: {file.fileId},
            folderIds: {},
            sourceFolderId: file.folderId,
          ));
        },
        onDelete: () {
          Navigator.pop(ctx);
          _deleteFile(file);
        },
      ),
    );
  }

  void _showShareSheet(FileRecord file) {
    final existing = context.read<TransferCubit>().getShareJob(file.fileId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: file,
        shareUrl: existing?.shareUrl,
        onCopyLink: (pwd, expiryDays) async {
          context
              .read<BrowserBloc>()
              .add(EnqueueShare(file, password: pwd, expiryDays: expiryDays));

          if (!mounted || !ctx.mounted) return;
          Navigator.pop(ctx);

        },
      ),
    );
  }

  Future<void> _renameFile(FileRecord file) async {
    final ctrl = TextEditingController(text: file.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Rename File'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      context.read<BrowserBloc>().add(RenameFile(file.fileId, result));
    }
  }

  Future<void> _deleteFile(FileRecord file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Delete "${file.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) context.read<BrowserBloc>().add(DeleteFile(file.fileId));
  }

  void _showFolderActions(FolderRecord folder) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.folder_rounded,
                        color: colors.fileFolder, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        folder.name,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _FolderActionTile(
                icon: AppIcons.rename,
                label: 'Rename',
                onTap: () {
                  Navigator.pop(ctx);
                  _renameFolder(folder);
                },
              ),
              _FolderActionTile(
                icon: AppIcons.cut,
                label: 'Cut',
                onTap: () {
                  Navigator.pop(ctx);
                  context.read<BrowserBloc>().add(SetClipboard(
                        mode: ClipboardMode.move,
                        fileIds: {},
                        folderIds: {folder.id},
                        sourceFolderId: folder.parentId,
                      ));
                },
              ),
              _FolderActionTile(
                icon: AppIcons.copyLink,
                label: 'Copy',
                onTap: () {
                  Navigator.pop(ctx);
                  context.read<BrowserBloc>().add(SetClipboard(
                        mode: ClipboardMode.copy,
                        fileIds: {},
                        folderIds: {folder.id},
                        sourceFolderId: folder.parentId,
                      ));
                },
              ),
              _FolderActionTile(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                color: colors.error,
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteFolder(folder);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameFolder(FolderRecord folder) async {
    final ctrl = TextEditingController(text: folder.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Rename Folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      context.read<BrowserBloc>().add(RenameFolder(folder.id, result));
    }
  }

  Future<void> _deleteFolder(FolderRecord folder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Delete "${folder.name}"?'),
        content: const Text('Only empty folders can be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) context.read<BrowserBloc>().add(DeleteFolder(folder.id));
  }

  Future<void> _confirmBatchDelete(BuildContext context, BrowserState state) async {
    final count = state.selectedFileIds.length + state.selectedFolderIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Delete $count selected items?'),
        content: const Text('Selected files and empty folders will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      context.read<BrowserBloc>().add(BatchDelete());
    }
  }

  void _setClipboard(ClipboardMode mode) {
    final state = context.read<BrowserBloc>().state;
    context.read<BrowserBloc>().add(SetClipboard(
      mode: mode,
      fileIds: Set.from(state.selectedFileIds),
      folderIds: Set.from(state.selectedFolderIds),
      sourceFolderId: state.currentFolderId,
    ));
  }

  Future<void> _downloadAndView(FileRecord file) async {
    context.read<BrowserBloc>().add(EnqueueDownload(file));
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('New Folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      context.read<BrowserBloc>().add(CreateFolder(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BrowserBloc, BrowserState>(
      listener: (context, state) {},
      builder: (context, state) {
        if (state.isLoading && !state.isInitialized) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        return PopScope(
          canPop: !state.isMultiSelect && state.currentFolderId == null && state.category == null,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (state.isMultiSelect) {
              context.read<BrowserBloc>().add(ClearSelection());
            } else {
              context.read<BrowserBloc>().add(NavigateUp());
            }
          },
          child: _buildScaffold(context, state),
        );
      },
    );
  }

  Widget _buildScaffold(BuildContext context, BrowserState state) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final totalSelected = state.selectedFileIds.length + state.selectedFolderIds.length;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: state.isMultiSelect
          ? AppBar(
              backgroundColor: colors.bgPrimary,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.close_rounded, color: colors.textPrimary),
                onPressed: () => context.read<BrowserBloc>().add(ClearSelection()),
              ),
              title: Text(
                '$totalSelected Selected',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: Icon(Icons.select_all_rounded, color: colors.textPrimary),
                  tooltip: 'Select All',
                  onPressed: () {
                    final bloc = context.read<BrowserBloc>();
                    for (final f in state.folders) {
                      if (!state.selectedFolderIds.contains(f.id)) {
                        bloc.add(ToggleItemSelection(f.id, isFolder: true));
                      }
                    }
                    for (final f in state.files) {
                      if (!state.selectedFileIds.contains(f.fileId)) {
                        bloc.add(ToggleItemSelection(f.fileId, isFolder: false));
                      }
                    }
                  },
                ),
                IconButton(
                  icon: Icon(AppIcons.copyLink, color: colors.textPrimary),
                  tooltip: 'Copy',
                  onPressed: () => _setClipboard(ClipboardMode.copy),
                ),
                IconButton(
                  icon: Icon(AppIcons.cut, color: colors.textPrimary),
                  tooltip: 'Cut (Move)',
                  onPressed: () => _setClipboard(ClipboardMode.move),
                ),
                if (state.selectedFileIds.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.file_download_outlined, color: colors.accentPrimary),
                    tooltip: 'Download Selected',
                    onPressed: () {
                      final bloc = context.read<BrowserBloc>();
                      for (final fileId in state.selectedFileIds) {
                        final file = state.files.where((f) => f.fileId == fileId).firstOrNull;
                        if (file != null) {
                          bloc.add(EnqueueDownload(file));
                        }
                      }
                      bloc.add(ClearSelection());
                    },
                  ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, color: colors.error),
                  tooltip: 'Delete Selected',
                  onPressed: () => _confirmBatchDelete(context, state),
                ),
              ],
            )
          : AppBar(
              backgroundColor: colors.bgPrimary,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.menu_rounded, color: colors.textPrimary),
                onPressed: () => MobileShell.of(context)?.openDrawer(),
              ),
              title: Text(
                'Files',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
              actions: [
                ValueListenableBuilder<int>(
                  valueListenable: ServiceLocator.instance.syncQueue.pendingCountNotifier,
                  builder: (context, pendingCount, _) {
                    final badgeText = pendingCount > 9 ? '+9' : '+$pendingCount';
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton(
                          icon: Icon(Icons.sync_rounded, color: colors.textPrimary),
                          tooltip: 'Sync Center',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const SyncScreen()),
                            );
                          },
                        ),
                        if (pendingCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: colors.accentPrimary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              child: Text(
                                badgeText,
                                style: TextStyle(
                                  color: colors.bgPrimary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                IconButton(
                  icon: Icon(Icons.download_rounded, color: colors.textPrimary),
                  onPressed: () => MobileShell.of(context)?.switchTab(3),
                ),
              ],
            ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildSearchBar(),
              _buildFilterTabs(colors, state),
              const SizedBox(height: 12),
              if (state.isLoading && state.isInitialized)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    if (state.folders.isEmpty && state.files.isEmpty)
                      _buildEmptyState(colors, state)
                    else ...[
                      if (state.folders.isNotEmpty) ...[
                        _buildSectionHeader('Folders',
                            trailing: IconButton(
                              icon: Icon(Icons.add, size: 20, color: colors.textPrimary),
                              onPressed: _createFolder,
                            )),
                        AppSurfaceCard(
                          radius: 24,
                          child: Column(
                            children: List.generate(state.folders.length, (fi) {
                              final f = state.folders[fi];
                              final count = state.folderItemCounts[f.id] ?? 0;
                              final isSelected = state.selectedFolderIds.contains(f.id);
                              return _FolderTile(
                                folder: f,
                                itemCount: count,
                                isSelected: isSelected,
                                isMultiSelect: state.isMultiSelect,
                                isLast: fi == state.folders.length - 1,
                                onTap: () {
                                  if (state.isMultiSelect) {
                                    context.read<BrowserBloc>().add(ToggleItemSelection(f.id, isFolder: true));
                                  } else {
                                    context.read<BrowserBloc>().add(LoadDirectory(folderId: f.id));
                                  }
                                },
                                onLongPress: () {
                                  context.read<BrowserBloc>().add(ToggleItemSelection(f.id, isFolder: true));
                                },
                                onMore: () => _showFolderActions(f),
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      _buildSectionHeader('Files',
                          trailing: GestureDetector(
                            onTap: () =>
                                context.read<BrowserBloc>().add(SortOptionChanged(BrowserSortOption.name)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Name',
                                    style: TextStyle(
                                        color: colors.textSecondary, fontSize: 13)),
                                const SizedBox(width: 4),
                                Icon(
                                    state.sortAscending
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded,
                                    size: 14,
                                    color: colors.textSecondary),
                              ],
                            ),
                          )),
                      if (state.files.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text(
                              'No files in this folder.',
                              style: TextStyle(color: colors.textTertiary, fontSize: 13),
                            ),
                          ),
                        )
                      else
                        AppSurfaceCard(
                          radius: 24,
                          child: Column(
                            children: List.generate(state.files.length, (fi) {
                              final f = state.files[fi];
                              final isSelected = state.selectedFileIds.contains(f.fileId);
                              return _FileTile(
                                file: f,
                                isSelected: isSelected,
                                isMultiSelect: state.isMultiSelect,
                                isLast: fi == state.files.length - 1,
                                onTap: () {
                                  if (state.isMultiSelect) {
                                    context.read<BrowserBloc>().add(ToggleItemSelection(f.fileId, isFolder: false));
                                  } else {
                                    _downloadAndView(f);
                                  }
                                },
                                onLongPress: () {
                                  context.read<BrowserBloc>().add(ToggleItemSelection(f.fileId, isFolder: false));
                                },
                                onMore: () => _showFileDetail(f),
                              );
                            }),
                          ),
                        ),
                    ],
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildFloatingClipboardBar(colors, state),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingClipboardBar(AppColorsExtension colors, BrowserState state) {
    if (!state.hasClipboard) return const SizedBox.shrink();

    final count = state.clipboardFileIds.length + state.clipboardFolderIds.length;
    final isMove = state.clipboardMode == ClipboardMode.move;
    final label = isMove ? 'Move $count item(s)' : 'Copy $count item(s)';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.accentPrimary.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: colors.glowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            isMove ? Icons.drive_file_move_outlined : Icons.copy_rounded,
            color: colors.accentPrimary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () {
              context.read<BrowserBloc>().add(ClearClipboard());
            },
            child: Text(
              'Cancel',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {
              context.read<BrowserBloc>().add(PasteClipboard(state.currentFolderId));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accentPrimary,
              foregroundColor: colors.bgPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Paste Here',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppColorsExtension colors, BrowserState state) {
    final isSearch = state.searchQuery.isNotEmpty;
    final isFilter = state.category != null;

    IconData iconData = Icons.folder_open_rounded;
    String title = 'This folder is empty';
    String description = 'Upload files or create a subfolder to get started.';

    if (isSearch) {
      iconData = Icons.search_off_rounded;
      title = 'No items found';
      description = 'No files or folders matched "${state.searchQuery}".';
    } else if (isFilter) {
      iconData = Icons.filter_alt_off_rounded;
      title = 'No ${state.category} files';
      description = 'There are no files matching this category in this location.';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colors.fileFolderBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconData,
              size: 40,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return AppSearchField(
      hintText: 'Search files and folders...',
      onChanged: (v) =>
          context.read<BrowserBloc>().add(SearchQueryChanged(v)),
    );
  }

  Widget _buildFilterTabs(AppColorsExtension colors, BrowserState state) {
    final filters = [
      {'label': 'All', 'key': null},
      {'label': 'Images', 'key': 'images'},
      {'label': 'Videos', 'key': 'videos'},
      {'label': 'Docs', 'key': 'docs'},
      {'label': 'Audio', 'key': 'others'},
    ];

    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (ctx, i) {
          final filter = filters[i];
          final isSelected = state.category == filter['key'];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () {
                context.read<BrowserBloc>().add(LoadDirectory(
                    folderId: state.currentFolderId, category: filter['key']));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: isSelected ? colors.accentPrimary : colors.bgSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  filter['label'] as String,
                  style: TextStyle(
                    color: isSelected ? colors.bgPrimary : colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final FolderRecord folder;
  final int itemCount;
  final bool isSelected;
  final bool isMultiSelect;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  const _FolderTile({
    required this.folder,
    required this.itemCount,
    required this.isSelected,
    required this.isMultiSelect,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM yyyy').format(folder.createdAt);
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? colors.accentPrimary.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? colors.accentPrimary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.fileFolderBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.folder_rounded,
                      color: colors.fileFolder, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(folder.name,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              )),
                      const SizedBox(height: 1),
                      Text(
                        '$itemCount items • $dateStr',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (isMultiSelect)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected ? colors.accentPrimary : colors.textTertiary,
                      size: 22,
                    ),
                  )
                else
                  IconButton(
                    icon: Icon(Icons.more_horiz_rounded, color: colors.textTertiary),
                    onPressed: onMore,
                  ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(indent: 10, endIndent: 10, color: colors.borderSubtle),
      ],
    );
  }
}

class _FolderActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _FolderActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final tint = color ?? colors.textPrimary;

    return ListTile(
      leading: Icon(icon, color: tint),
      title: Text(
        label,
        style: TextStyle(
          color: tint,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _FileTile extends StatelessWidget {
  final FileRecord file;
  final bool isSelected;
  final bool isMultiSelect;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  const _FileTile({
    required this.file,
    required this.isSelected,
    required this.isMultiSelect,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM yyyy').format(file.uploadedAt);

    return BlocBuilder<TransferCubit, TransferState>(
      builder: (context, transferState) {
        final activeTask = transferState.activeTasks
            .where((t) => t.id == file.fileId || t.name == file.name)
            .firstOrNull;
        final isDownloading = activeTask != null && activeTask.isActive;
        final progress = activeTask?.progress ?? 0.0;
        final percentText = '${(progress * 100).toInt()}%';

        return Column(
          children: [
            GestureDetector(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? colors.accentPrimary.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? colors.accentPrimary : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildLeading(colors, isDownloading, progress, percentText),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 1),
                              Text(
                                isDownloading
                                    ? 'Downloading... $percentText • ${(activeTask.speedKbps / 1024).toStringAsFixed(1)} MB/s'
                                    : '${file.formattedSize} • $dateStr',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDownloading ? colors.accentPrimary : colors.textSecondary,
                                  fontWeight: isDownloading ? FontWeight.w600 : FontWeight.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (isMultiSelect)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              isSelected
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: isSelected ? colors.accentPrimary : colors.textTertiary,
                              size: 22,
                            ),
                          )
                        else
                          IconButton(
                            icon: Icon(Icons.more_horiz_rounded, color: colors.textTertiary),
                            onPressed: onMore,
                          ),
                      ],
                    ),
                    if (isDownloading) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: colors.bgSurfaceInset,
                          valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!isLast)
              Divider(indent: 10, endIndent: 10, color: colors.borderSubtle),
          ],
        );
      },
    );
  }

  Widget _buildLeading(AppColorsExtension colors, bool isDownloading, double progress, String percentText) {
    if (!isDownloading) {
      return ThumbnailWidget(
        file: file,
        width: 44,
        height: 44,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ThumbnailWidget(
              file: file,
              width: 44,
              height: 44,
            ),
            Container(
              color: colors.bgPrimary.withValues(alpha: 0.65),
            ),
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                backgroundColor: colors.bgSurfaceInset.withValues(alpha: 0.5),
              ),
            ),
            Text(
              percentText,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
