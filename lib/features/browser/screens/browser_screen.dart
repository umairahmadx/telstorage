import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/folder_record.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/thumbnail_widget.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../shared/widgets/share_link_sheet.dart';
import '../../../shared/widgets/file_detail_sheet.dart';
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

  void _snack(String msg, {bool success = false}) {}

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
          _snack('Cut "${file.name}". Navigate to target folder and tap Paste Here.', success: true);
        },
        onCopy: () {
          Navigator.pop(ctx);
          context.read<BrowserBloc>().add(SetClipboard(
            mode: ClipboardMode.copy,
            fileIds: {file.fileId},
            folderIds: {},
            sourceFolderId: file.folderId,
          ));
          _snack('Copied "${file.name}". Navigate to target folder and tap Paste Here.', success: true);
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

          _snack('Sharing started. Check "Transfer" tab for progress.',
              success: true);
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
    final total = state.selectedFileIds.length + state.selectedFolderIds.length;
    context.read<BrowserBloc>().add(SetClipboard(
      mode: mode,
      fileIds: Set.from(state.selectedFileIds),
      folderIds: Set.from(state.selectedFolderIds),
      sourceFolderId: state.currentFolderId,
    ));
    final actionLabel = mode == ClipboardMode.move ? 'Cut' : 'Copied';
    _snack('$actionLabel $total item(s). Navigate to destination and tap Paste Here.', success: true);
  }

  Future<void> _downloadAndView(FileRecord file) async {
    context.read<BrowserBloc>().add(EnqueueDownload(file));
    _snack('Downloading "${file.name}"...', success: true);
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
      listener: (context, state) {
        if (state.errorMessage != null) _snack(state.errorMessage!);
      },
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
                  icon: Icon(Icons.copy_rounded, color: colors.textPrimary),
                  tooltip: 'Copy',
                  onPressed: () => _setClipboard(ClipboardMode.copy),
                ),
                IconButton(
                  icon: Icon(Icons.content_cut_rounded, color: colors.textPrimary),
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
                      _snack('${state.selectedFileIds.length} file(s) added to downloads', success: true);
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
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Files',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (state.pendingActionsCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.accentPrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.accentPrimary.withValues(alpha: 0.4), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_upload_outlined, size: 12, color: colors.accentPrimary),
                          const SizedBox(width: 4),
                          Text(
                            '${state.pendingActionsCount}',
                            style: TextStyle(
                              color: colors.accentPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: Icon(Icons.file_download_outlined, color: colors.textPrimary),
                  onPressed: () => MobileShell.of(context)?.switchTab(3),
                ),
              ],
            ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildSearchBar(colors),
              _buildFilterTabs(colors, state),
              const SizedBox(height: 12),
              if (state.isLoading && state.isInitialized)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    if (state.folders.isNotEmpty) ...[
                      _buildSectionHeader('Folders',
                          trailing: IconButton(
                            icon: Icon(Icons.add, size: 20, color: colors.textPrimary),
                            onPressed: _createFolder,
                          )),
                      ...state.folders.map((f) {
                        final count = state.folderItemCounts[f.id] ?? 0;
                        final isSelected = state.selectedFolderIds.contains(f.id);
                        return _FolderTile(
                          folder: f,
                          itemCount: count,
                          isSelected: isSelected,
                          isMultiSelect: state.isMultiSelect,
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
                          onMore: () {
                            if (state.isMultiSelect) {
                              context.read<BrowserBloc>().add(ToggleItemSelection(f.id, isFolder: true));
                            }
                          },
                        );
                      }),
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
                    ...state.files.map((f) {
                      final isSelected = state.selectedFileIds.contains(f.fileId);
                      return _FileTile(
                        file: f,
                        isSelected: isSelected,
                        isMultiSelect: state.isMultiSelect,
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

  Widget _buildSearchBar(AppColorsExtension colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(25),
        ),
        child: TextField(
          onChanged: (v) => context.read<BrowserBloc>().add(SearchQueryChanged(v)),
          style: TextStyle(color: colors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search files and folders...',
            hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded,
                color: colors.textTertiary, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
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
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM yyyy').format(folder.createdAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? colors.accentPrimary.withValues(alpha: 0.12) : colors.bgSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? colors.accentPrimary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: colors.fileFolderBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.folder_rounded,
                    color: colors.fileFolder, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(folder.name,
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 2),
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
    );
  }
}

class _FileTile extends StatelessWidget {
  final FileRecord file;
  final bool isSelected;
  final bool isMultiSelect;
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

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? colors.accentPrimary.withValues(alpha: 0.12) : colors.bgSurface,
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
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.name,
                              style: Theme.of(context).textTheme.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
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
        );
      },
    );
  }

  Widget _buildLeading(AppColorsExtension colors, bool isDownloading, double progress, String percentText) {
    if (!isDownloading) {
      return ThumbnailWidget(
        file: file,
        width: 52,
        height: 52,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ThumbnailWidget(
              file: file,
              width: 52,
              height: 52,
            ),
            Container(
              color: colors.bgPrimary.withValues(alpha: 0.65),
            ),
            SizedBox(
              width: 38,
              height: 38,
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
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
