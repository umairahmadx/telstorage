import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/folder_record.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_common_widgets.dart';
import '../../../shared/widgets/app_search_field.dart';
import '../../../shared/widgets/file_detail_sheet.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../shared/widgets/share_link_sheet.dart';
import '../../downloads/bloc/transfer_cubit.dart';
import '../bloc/browser_bloc.dart';
import 'widgets/browser_batch_bar.dart';
import 'widgets/browser_file_grid_tile.dart';
import 'widgets/browser_file_tile.dart';
import 'widgets/browser_folder_tile.dart';
import 'widgets/browser_sort_sheet.dart';

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
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<BrowserBloc>().add(LoadDirectory(
        folderId: widget.currentFolderId, category: widget.category));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          context.read<BrowserBloc>().add(EnqueueDownload(file));
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
        onCopyLink: (pwd, expiryDays, vanitySlug) async {
          context
              .read<BrowserBloc>()
              .add(EnqueueShare(file, password: pwd, expiryDays: expiryDays, vanitySlug: vanitySlug));

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
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) context.read<BrowserBloc>().add(DeleteFile(file.fileId));
  }

  Future<void> _deleteFolder(FolderRecord folder) async {
    final repository = ServiceLocator.instance.storageRepository;
    final fileCount = repository.getFolderDescendantFileCount(folder.id);
    final folderCount = repository.getFolderDescendantFolderCount(folder.id);
    final nestedFolderCount = folderCount - 1;
    final fileLabel = fileCount == 1 ? 'file' : 'files';
    final folderLabel = nestedFolderCount == 1 ? 'subfolder' : 'subfolders';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Delete "${folder.name}" and everything inside?'),
        content: Text(
          'This will permanently delete $fileCount $fileLabel and '
          '$nestedFolderCount nested $folderLabel. All files and folders inside '
          'this folder tree will be removed in one sync operation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );

    if (!mounted || ok != true) return;
    context.read<BrowserBloc>().add(DeleteFolder(folder.id));
  }

  void _showSortOptions(BrowserState state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => BrowserSortSheet(
        currentSort: state.sortOption,
        isAscending: state.sortAscending,
        currentGroup: state.groupOption,
        onSortChanged: (opt) =>
            context.read<BrowserBloc>().add(SortOptionChanged(opt)),
        onGroupChanged: (opt) =>
            context.read<BrowserBloc>().add(GroupOptionChanged(opt)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return BlocBuilder<BrowserBloc, BrowserState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => MobileShell.of(context)?.openDrawer(),
            ),
            title: Text(state.category != null
                ? state.category!.toUpperCase()
                : 'Files'),
            actions: [
              if (state.pendingActionsCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Chip(
                    avatar: const Icon(Icons.cloud_upload_rounded, size: 14),
                    label: Text('${state.pendingActionsCount} pending'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              IconButton(
                icon: Icon(state.isGridView
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded),
                onPressed: () =>
                    context.read<BrowserBloc>().add(ToggleViewMode()),
              ),
              IconButton(
                icon: const Icon(Icons.sort_rounded),
                onPressed: () => _showSortOptions(state),
              ),
            ],
          ),
          body: Column(
            children: [
              AppSearchField(
                hintText: 'Search files and folders…',
                controller: _searchCtrl,
                onChanged: (q) =>
                    context.read<BrowserBloc>().add(SearchQueryChanged(q)),
              ),
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : (state.folders.isEmpty && state.files.isEmpty)
                        ? const AppEmptyState(
                            message: 'No files or folders found',
                            icon: Icons.folder_open_rounded,
                          )
                        : state.isGridView
                            ? _buildGridView(colors, state)
                            : _buildListView(colors, state),
              ),
            ],
          ),
          bottomNavigationBar: state.isMultiSelect
              ? BrowserBatchBar(
                  selectedCount: state.selectedFolderIds.length +
                      state.selectedFileIds.length,
                  onClearSelection: () =>
                      context.read<BrowserBloc>().add(ClearSelection()),
                  onDelete: () =>
                      context.read<BrowserBloc>().add(BatchDelete()),
                  onMove: () => context.read<BrowserBloc>().add(SetClipboard(
                        mode: ClipboardMode.move,
                        fileIds: state.selectedFileIds,
                        folderIds: state.selectedFolderIds,
                        sourceFolderId: state.currentFolderId,
                      )),
                  onCopy: () => context.read<BrowserBloc>().add(SetClipboard(
                        mode: ClipboardMode.copy,
                        fileIds: state.selectedFileIds,
                        folderIds: state.selectedFolderIds,
                        sourceFolderId: state.currentFolderId,
                      )),
                )
              : null,
        );
      },
    );
  }

  Widget _buildListView(AppColorsExtension colors, BrowserState state) {
    final totalCount = state.folders.length + state.files.length;
    return ListView.builder(
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (index < state.folders.length) {
          final folder = state.folders[index];
          final isSel = state.selectedFolderIds.contains(folder.id);
          return BrowserFolderTile(
            folder: folder,
            itemCount: state.folderItemCounts[folder.id] ?? 0,
            isSelected: isSel,
            isMultiSelect: state.isMultiSelect,
            onTap: () {
              if (state.isMultiSelect) {
                context.read<BrowserBloc>().add(
                    ToggleItemSelection(folder.id, isFolder: true));
              } else {
                context
                    .read<BrowserBloc>()
                    .add(LoadDirectory(folderId: folder.id));
              }
            },
            onLongPress: () => context
                .read<BrowserBloc>()
                .add(ToggleItemSelection(folder.id, isFolder: true)),
            onMore: () => _deleteFolder(folder),
          );
        } else {
          final fileIndex = index - state.folders.length;
          final file = state.files[fileIndex];
          final isSel = state.selectedFileIds.contains(file.fileId);
          return BrowserFileTile(
            file: file,
            isSelected: isSel,
            isMultiSelect: state.isMultiSelect,
            onTap: () {
              if (state.isMultiSelect) {
                context.read<BrowserBloc>().add(
                    ToggleItemSelection(file.fileId, isFolder: false));
              } else {
                _showFileDetail(file);
              }
            },
            onLongPress: () => context.read<BrowserBloc>().add(
                ToggleItemSelection(file.fileId, isFolder: false)),
            onMore: () => _showFileDetail(file),
          );
        }
      },
    );
  }

  Widget _buildGridView(AppColorsExtension colors, BrowserState state) {
    final totalCount = state.folders.length + state.files.length;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (index < state.folders.length) {
          final folder = state.folders[index];
          final isSel = state.selectedFolderIds.contains(folder.id);
          return BrowserFolderTile(
            folder: folder,
            itemCount: state.folderItemCounts[folder.id] ?? 0,
            isSelected: isSel,
            isMultiSelect: state.isMultiSelect,
            onTap: () {
              if (state.isMultiSelect) {
                context.read<BrowserBloc>().add(
                    ToggleItemSelection(folder.id, isFolder: true));
              } else {
                context
                    .read<BrowserBloc>()
                    .add(LoadDirectory(folderId: folder.id));
              }
            },
            onLongPress: () => context
                .read<BrowserBloc>()
                .add(ToggleItemSelection(folder.id, isFolder: true)),
            onMore: () => _deleteFolder(folder),
          );
        } else {
          final fileIndex = index - state.folders.length;
          final file = state.files[fileIndex];
          final isSel = state.selectedFileIds.contains(file.fileId);
          return BrowserFileGridTile(
            file: file,
            isSelected: isSel,
            isMultiSelect: state.isMultiSelect,
            onTap: () {
              if (state.isMultiSelect) {
                context.read<BrowserBloc>().add(
                    ToggleItemSelection(file.fileId, isFolder: false));
              } else {
                _showFileDetail(file);
              }
            },
            onLongPress: () => context.read<BrowserBloc>().add(
                ToggleItemSelection(file.fileId, isFolder: false)),
            onMore: () => _showFileDetail(file),
          );
        }
      },
    );
  }
}
