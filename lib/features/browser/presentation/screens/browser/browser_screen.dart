/*
 * File: browser_screen.dart
 * Description: File and folder browser view providing directory navigation, search, and file actions using centralized shared widgets.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_search_field.dart';
import 'package:telstorage/shared/widgets/bars/app_batch_action_bar.dart';
import 'package:telstorage/shared/widgets/feedback/app_empty_state.dart';
import 'package:telstorage/shared/widgets/tiles/app_file_grid_tile.dart';
import 'package:telstorage/shared/widgets/tiles/app_file_tile.dart';
import 'package:telstorage/shared/widgets/tiles/app_folder_tile.dart';
import 'package:telstorage/shared/widgets/typography/app_section_label.dart';
import 'viewmodel/browser_view_model.dart';
import 'widgets/browser_dialogs.dart';

/// Screen component rendering file directory navigation and management.
class BrowserScreen extends StatefulWidget {
  /// Initial folder ID to open.
  final String? currentFolderId;

  /// Optional media category filter.
  final String? category;

  /// Constructs BrowserScreen.
  const BrowserScreen({super.key, this.currentFolderId, this.category});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

/// State controller for BrowserScreen handling search and UI updates.
class _BrowserScreenState extends State<BrowserScreen> {
  /// Search input text controller.
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return BlocConsumer<BrowserBloc, BrowserState>(
      listener: (context, state) {
        if (state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              backgroundColor: colors.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final canGoUp = state.currentFolderId != null ||
            (state.category != null && widget.category == null);

        return PopScope(
          canPop: !canGoUp && !Navigator.canPop(context),
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (canGoUp) {
              context.read<BrowserBloc>().add(NavigateUp());
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          },
          child: Scaffold(
            backgroundColor: colors.bgPrimary,
          appBar: AppBar(
            backgroundColor: colors.bgPrimary,
            elevation: 0,
            leading: Navigator.canPop(context)
                ? IconButton(
                    icon: Icon(Icons.arrow_back_rounded,
                        color: colors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  )
                : (state.currentFolderId != null
                    ? IconButton(
                        icon: Icon(Icons.arrow_back_rounded,
                            color: colors.textPrimary),
                        onPressed: () => context
                            .read<BrowserBloc>()
                            .add(NavigateUp()),
                      )
                    : null),
            title: Text(
              widget.category != null
                  ? '${widget.category![0].toUpperCase()}${widget.category!.substring(1)}'
                  : 'Files',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            actions: [
              IconButton(
                icon: Icon(
                    state.isGridView
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded,
                    color: colors.textPrimary),
                tooltip: state.isGridView ? 'List View' : 'Grid View',
                onPressed: () =>
                    context.read<BrowserBloc>().add(ToggleViewMode()),
              ),
              IconButton(
                icon: Icon(Icons.sort_rounded, color: colors.textPrimary),
                tooltip: 'Sort & Filter',
                onPressed: () => BrowserDialogs.showSortSheet(context, state),
              ),
            ],
          ),
          body: Column(
            children: [
              // Search field
              AppSearchField(
                controller: _searchCtrl,
                hintText: 'Search files and folders...',
                onChanged: (q) =>
                    context.read<BrowserBloc>().add(SearchQueryChanged(q)),
              ),

              // Category Pills
              if (widget.category == null) _buildCategoryFilter(state, colors),

              // Clipboard Banner
              if (state.hasClipboard) _buildClipboardBanner(state, colors),

              // Main content area
              Expanded(
                child: state.isLoading && !state.isInitialized
                    ? const Center(child: CircularProgressIndicator())
                    : _buildContent(state),
              ),
              if (state.isMultiSelect)
                AppBatchActionBar(
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
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds clipboard indicator banner.
  Widget _buildClipboardBanner(
      BrowserState state, AppColorsExtension colors) {
    final count =
        state.clipboardFileIds.length + state.clipboardFolderIds.length;
    final isMove = state.clipboardMode == ClipboardMode.move;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colors.bgSurfaceInset,
      child: Row(
        children: [
          Icon(isMove ? Icons.drive_file_move_outlined : Icons.copy_rounded,
              size: 18),
          const SizedBox(width: 8),
          Text('$count items to ${isMove ? "move" : "copy"}'),
          const Spacer(),
          TextButton(
            onPressed: () =>
                context.read<BrowserBloc>().add(ClearClipboard()),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => context
                .read<BrowserBloc>()
                .add(PasteClipboard(state.currentFolderId)),
            child: const Text('Paste Here'),
          ),
        ],
      ),
    );
  }

  /// Builds horizontal scrollable category filter pills.
  Widget _buildCategoryFilter(BrowserState state, AppColorsExtension colors) {
    const categories = [
      ('All', null),
      ('Images', 'image'),
      ('Videos', 'video'),
      ('Docs', 'document'),
      ('Audio', 'audio'),
      ('Archives', 'archive'),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final (label, cat) = categories[i];
          final isSelected = state.category == cat;
          return FilterChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (_) {
              context.read<BrowserBloc>().add(LoadDirectory(
                    folderId: state.currentFolderId,
                    category: cat,
                  ));
            },
            backgroundColor: colors.bgSurface,
            selectedColor: colors.accentPrimary.withValues(alpha: 0.2),
            labelStyle: TextStyle(
              color: isSelected ? colors.accentPrimary : colors.textSecondary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
            side: BorderSide(
              color: isSelected ? colors.accentPrimary : colors.borderSubtle,
            ),
          );
        },
      ),
    );
  }

  /// Builds directory files & folders content list or grid.
  Widget _buildContent(BrowserState state) {
    if (state.folders.isEmpty && state.files.isEmpty) {
      return const AppEmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Folder is empty',
        subtitle: 'Upload files or create subfolders to get started.',
      );
    }

    if (state.isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.95,
        ),
        itemCount: state.files.length,
        itemBuilder: (ctx, i) {
          final file = state.files[i];
          final isSelected = state.selectedFileIds.contains(file.fileId);
          return AppFileGridTile(
            file: file,
            isSelected: isSelected,
            isSelectionMode: state.isMultiSelect,
            onTap: () {
              if (state.isMultiSelect) {
                context.read<BrowserBloc>().add(
                    ToggleItemSelection(file.fileId, isFolder: false));
              } else {
                BrowserDialogs.showFileDetail(context, file);
              }
            },
            onLongPress: () {
              if (!state.isMultiSelect) {
                context.read<BrowserBloc>().add(
                    ToggleItemSelection(file.fileId, isFolder: false));
              }
            },
            onActionTap: () => BrowserDialogs.showFileDetail(context, file),
          );
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (state.folders.isNotEmpty) ...[
          const AppSectionLabel(label: 'Folders'),
          ...state.folders.map((folder) {
            final isSelected = state.selectedFolderIds.contains(folder.id);
            return AppFolderTile(
              folder: folder,
              itemCount: 0,
              isSelected: isSelected,
              isSelectionMode: state.isMultiSelect,
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
              onLongPress: () {
                if (!state.isMultiSelect) {
                  context.read<BrowserBloc>().add(
                      ToggleItemSelection(folder.id, isFolder: true));
                }
              },
              onActionTap: () => BrowserDialogs.showFolderDetail(context, folder),
            );
          }),
          const SizedBox(height: 12),
        ],
        if (state.files.isNotEmpty) ...[
          const AppSectionLabel(label: 'Files'),
          ...state.files.map((file) {
            final isSelected = state.selectedFileIds.contains(file.fileId);
            return AppFileTile(
              file: file,
              isSelected: isSelected,
              isSelectionMode: state.isMultiSelect,
              onTap: () {
                if (state.isMultiSelect) {
                  context.read<BrowserBloc>().add(
                      ToggleItemSelection(file.fileId, isFolder: false));
                } else {
                  BrowserDialogs.showFileDetail(context, file);
                }
              },
              onLongPress: () {
                if (!state.isMultiSelect) {
                  context.read<BrowserBloc>().add(
                      ToggleItemSelection(file.fileId, isFolder: false));
                }
              },
              onActionTap: () => BrowserDialogs.showFileDetail(context, file),
            );
          }),
        ],
      ],
    );
  }
}
