/*
 * File: browser_screen.dart
 * Description: File and folder browser view providing directory navigation, search, and file actions using centralized shared widgets.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_search_field.dart';
import 'package:telstorage/shared/widgets/bars/app_batch_action_bar.dart';
import 'package:telstorage/shared/widgets/feedback/app_empty_state.dart';
import 'package:telstorage/shared/widgets/mobile_shell.dart';
import 'package:telstorage/shared/widgets/tiles/app_file_tile.dart';
import 'package:telstorage/shared/widgets/tiles/app_folder_tile.dart';
import 'package:telstorage/shared/widgets/typography/app_section_label.dart';
import 'viewmodel/browser_view_model.dart';
import 'widgets/browser_dialogs.dart';
import 'widgets/browser_floating_clipboard_bar.dart';
import 'widgets/browser_grid_content.dart';

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

        String? currentFolderName;
        if (state.currentFolderId != null) {
          try {
            if (ServiceLocator.instance.isInitialized) {
              currentFolderName = ServiceLocator.instance.storageRepository
                  .getFolder(state.currentFolderId!)
                  ?.name;
            }
          } catch (_) {}
        }

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
              leading: canGoUp
                  ? IconButton(
                      icon: Icon(Icons.arrow_back_rounded,
                          color: colors.textPrimary),
                      onPressed: () =>
                          context.read<BrowserBloc>().add(NavigateUp()),
                    )
                  : IconButton(
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: () => MobileShell.of(context)?.openDrawer(),
                    ),
              title: Text(
                widget.category != null
                    ? '${widget.category![0].toUpperCase()}${widget.category!.substring(1)}'
                    : (currentFolderName ?? 'Files'),
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
            body: Stack(
              children: [
                Column(
                  children: [
                    // Search field
                    AppSearchField(
                      controller: _searchCtrl,
                      hintText: 'Search files and folders...',
                      onChanged: (q) => context
                          .read<BrowserBloc>()
                          .add(SearchQueryChanged(q)),
                    ),

                    // Category Pills (only displayed at root directory)
                    if (widget.category == null &&
                        state.currentFolderId == null)
                      _buildCategoryFilter(state, colors),

                    // Main content area
                    Expanded(
                      child: state.isLoading && !state.isInitialized
                          ? const Center(child: CircularProgressIndicator())
                          : _buildContent(state),
                    ),

                    // Batch selection action bar
                    if (state.isMultiSelect)
                      AppBatchActionBar(
                        selectedCount: state.selectedFolderIds.length +
                            state.selectedFileIds.length,
                        onClearSelection: () =>
                            context.read<BrowserBloc>().add(ClearSelection()),
                        onDelete: () =>
                            context.read<BrowserBloc>().add(BatchDelete()),
                        onMove: () =>
                            context.read<BrowserBloc>().add(SetClipboard(
                                  mode: ClipboardMode.move,
                                  fileIds: state.selectedFileIds,
                                  folderIds: state.selectedFolderIds,
                                  sourceFolderId: state.currentFolderId,
                                )),
                        onCopy: () =>
                            context.read<BrowserBloc>().add(SetClipboard(
                                  mode: ClipboardMode.copy,
                                  fileIds: state.selectedFileIds,
                                  folderIds: state.selectedFolderIds,
                                  sourceFolderId: state.currentFolderId,
                                )),
                      ),
                  ],
                ),

                // Floating non-shifting clipboard overlay bar
                if (state.hasClipboard)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: state.isMultiSelect ? 76 : 16,
                    child: BrowserFloatingClipboardBar(
                      state: state,
                      onCancel: () =>
                          context.read<BrowserBloc>().add(ClearClipboard()),
                      onPaste: () => context
                          .read<BrowserBloc>()
                          .add(PasteClipboard(state.currentFolderId)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
            selectedColor: colors.accentPrimary.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: isSelected ? colors.textPrimary : colors.textSecondary,
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
      return BrowserGridContent(
        state: state,
        onToggleSelection: (id, {required isFolder}) => context
            .read<BrowserBloc>()
            .add(ToggleItemSelection(id, isFolder: isFolder)),
        onOpenFolder: (folderId) =>
            context.read<BrowserBloc>().add(LoadDirectory(folderId: folderId)),
      );
    }

    bool isCutFolder(String id) =>
        state.clipboardMode == ClipboardMode.move &&
        state.clipboardFolderIds.contains(id);
    bool isCutFile(String id) =>
        state.clipboardMode == ClipboardMode.move &&
        state.clipboardFileIds.contains(id);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      children: [
        if (state.folders.isNotEmpty) ...[
          const AppSectionLabel(label: 'Folders'),
          ...state.folders.map((folder) {
            final isSelected = state.selectedFolderIds.contains(folder.id);
            final isCut = isCutFolder(folder.id);
            final tile = AppFolderTile(
              folder: folder,
              itemCount: state.folderItemCounts[folder.id] ?? 0,
              isSelected: isSelected,
              isSelectionMode: state.isMultiSelect,
              onTap: () {
                if (state.isMultiSelect) {
                  context
                      .read<BrowserBloc>()
                      .add(ToggleItemSelection(folder.id, isFolder: true));
                } else {
                  context
                      .read<BrowserBloc>()
                      .add(LoadDirectory(folderId: folder.id));
                }
              },
              onLongPress: () {
                if (!state.isMultiSelect) {
                  context
                      .read<BrowserBloc>()
                      .add(ToggleItemSelection(folder.id, isFolder: true));
                }
              },
              onActionTap: () =>
                  BrowserDialogs.showFolderDetail(context, folder),
            );
            if (isCut) {
              return Opacity(opacity: 0.45, child: tile);
            }
            return tile;
          }),
          const SizedBox(height: 12),
        ],
        if (state.files.isNotEmpty) ...[
          const AppSectionLabel(label: 'Files'),
          ...state.files.map((file) {
            final isSelected = state.selectedFileIds.contains(file.fileId);
            final isCut = isCutFile(file.fileId);
            final tile = AppFileTile(
              file: file,
              isSelected: isSelected,
              isSelectionMode: state.isMultiSelect,
              onTap: () {
                if (state.isMultiSelect) {
                  context
                      .read<BrowserBloc>()
                      .add(ToggleItemSelection(file.fileId, isFolder: false));
                } else {
                  BrowserDialogs.showFileDetail(context, file);
                }
              },
              onLongPress: () {
                if (!state.isMultiSelect) {
                  context
                      .read<BrowserBloc>()
                      .add(ToggleItemSelection(file.fileId, isFolder: false));
                }
              },
              onActionTap: () => BrowserDialogs.showFileDetail(context, file),
            );
            if (isCut) {
              return Opacity(opacity: 0.45, child: tile);
            }
            return tile;
          }),
        ],
      ],
    );
  }
}
