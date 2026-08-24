/// File: browser_screen.dart
/// Description: File and folder browser view providing directory navigation, search, and file actions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_common_widgets.dart';
import 'package:telstorage/shared/widgets/app_search_field.dart';
import 'package:telstorage/shared/widgets/mobile_shell.dart';
import 'viewmodel/browser_view_model.dart';
import 'widgets/browser_batch_bar.dart';
import 'widgets/browser_dialogs.dart';
import 'widgets/browser_file_grid_tile.dart';
import 'widgets/browser_file_tile.dart';
import 'widgets/browser_folder_tile.dart';

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
              backgroundColor: AppTheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final currentFolder = state.currentFolderId != null
            ? ServiceLocator.instance.storageRepository
                .getFolder(state.currentFolderId!)
            : null;

        final title = state.category != null
            ? '${state.category![0].toUpperCase()}${state.category!.substring(1)}'
            : (currentFolder?.name ?? 'Files');

        return Scaffold(
          appBar: AppBar(
            leading: (state.currentFolderId != null || state.category != null)
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () =>
                        context.read<BrowserBloc>().add(NavigateUp()),
                  )
                : IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => MobileShell.of(context)?.openDrawer(),
                  ),
            title: Text(title),
            actions: [
              IconButton(
                icon: Icon(state.isGridView
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded),
                onPressed: () =>
                    context.read<BrowserBloc>().add(ToggleViewMode()),
              ),
              IconButton(
                icon: const Icon(Icons.sort_rounded),
                onPressed: () => BrowserDialogs.showSortSheet(context, state),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: AppSearchField(
                  controller: _searchCtrl,
                  hintText: 'Search files and folders...',
                  onChanged: (q) => context
                      .read<BrowserBloc>()
                      .add(SearchQueryChanged(q)),
                ),
              ),
              if (state.hasClipboard) _buildClipboardBanner(state, colors),
              Expanded(
                child: state.isLoading && !state.isInitialized
                    ? const Center(child: CircularProgressIndicator())
                    : _buildContent(state),
              ),
              if (state.isMultiSelect)
                BrowserBatchBar(
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

  /// Builds directory files & folders content list or grid.
  Widget _buildContent(BrowserState state) {
    if (state.folders.isEmpty && state.files.isEmpty) {
      return const AppEmptyState(
        icon: Icons.folder_open_rounded,
        message: 'Folder is empty\nUpload files or create subfolders.',
      );
    }

    if (state.isGridView) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        itemCount: state.files.length,
        itemBuilder: (ctx, i) {
          final file = state.files[i];
          final isSelected = state.selectedFileIds.contains(file.fileId);
          return BrowserFileGridTile(
            file: file,
            isSelected: isSelected,
            isMultiSelect: state.isMultiSelect,
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
            onMore: () => BrowserDialogs.showFileDetail(context, file),
          );
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (state.folders.isNotEmpty) ...[
          const AppSectionLabel('Folders', fontSize: 16),
          ...state.folders.map((folder) {
            final isSelected = state.selectedFolderIds.contains(folder.id);
            return BrowserFolderTile(
              folder: folder,
              itemCount: 0,
              isSelected: isSelected,
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
              onLongPress: () {
                if (!state.isMultiSelect) {
                  context.read<BrowserBloc>().add(
                      ToggleItemSelection(folder.id, isFolder: true));
                }
              },
              onMore: () => BrowserDialogs.showFolderDetail(context, folder),
            );
          }),
          const SizedBox(height: 16),
        ],
        if (state.files.isNotEmpty) ...[
          const AppSectionLabel('Files', fontSize: 16),
          ...state.files.map((file) {
            final isSelected = state.selectedFileIds.contains(file.fileId);
            return BrowserFileTile(
              file: file,
              isSelected: isSelected,
              isMultiSelect: state.isMultiSelect,
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
              onMore: () => BrowserDialogs.showFileDetail(context, file),
            );
          }),
        ],
      ],
    );
  }
}
