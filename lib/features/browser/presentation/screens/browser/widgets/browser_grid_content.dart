/*
 * File: browser_grid_content.dart
 * Description: Grid layout content renderer displaying directory folders and files in separate adaptive sliver grids.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/shared/widgets/tiles/app_file_grid_tile.dart';
import 'package:telstorage/shared/widgets/tiles/app_folder_grid_tile.dart';
import 'package:telstorage/shared/widgets/typography/app_section_label.dart';
import '../viewmodel/browser_view_model.dart';
import 'browser_dialogs.dart';

/// Grid presentation layout for browser screen with folder and file sections.
class BrowserGridContent extends StatelessWidget {
  /// Associated browser state.
  final BrowserState state;

  /// Multi-selection callback for files and folders.
  final void Function(String id, {required bool isFolder}) onToggleSelection;

  /// Folder opening navigation callback.
  final void Function(String folderId) onOpenFolder;

  /// Constructs BrowserGridContent.
  const BrowserGridContent({
    super.key,
    required this.state,
    required this.onToggleSelection,
    required this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    bool isCutFolder(String id) =>
        state.clipboardMode == ClipboardMode.move &&
        state.clipboardFolderIds.contains(id);
    bool isCutFile(String id) =>
        state.clipboardMode == ClipboardMode.move &&
        state.clipboardFileIds.contains(id);

    return CustomScrollView(
      slivers: [
        if (state.folders.isNotEmpty) ...[
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverToBoxAdapter(
              child: AppSectionLabel(label: 'Folders'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.12,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final folder = state.folders[i];
                  final isSelected =
                      state.selectedFolderIds.contains(folder.id);
                  final isCut = isCutFolder(folder.id);
                  final tile = AppFolderGridTile(
                    folder: folder,
                    itemCount: state.folderItemCounts[folder.id] ?? 0,
                    isSelected: isSelected,
                    isSelectionMode: state.isMultiSelect,
                    onTap: () {
                      if (state.isMultiSelect) {
                        onToggleSelection(folder.id, isFolder: true);
                      } else {
                        onOpenFolder(folder.id);
                      }
                    },
                    onLongPress: () {
                      if (!state.isMultiSelect) {
                        onToggleSelection(folder.id, isFolder: true);
                      }
                    },
                    onActionTap: () =>
                        BrowserDialogs.showFolderDetail(context, folder),
                  );
                  if (isCut) {
                    return Opacity(opacity: 0.45, child: tile);
                  }
                  return tile;
                },
                childCount: state.folders.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
        if (state.files.isNotEmpty) ...[
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            sliver: SliverToBoxAdapter(
              child: AppSectionLabel(label: 'Files'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final file = state.files[i];
                  final isSelected =
                      state.selectedFileIds.contains(file.fileId);
                  final isCut = isCutFile(file.fileId);
                  final tile = AppFileGridTile(
                    file: file,
                    isSelected: isSelected,
                    isSelectionMode: state.isMultiSelect,
                    onTap: () {
                      if (state.isMultiSelect) {
                        onToggleSelection(file.fileId, isFolder: false);
                      } else {
                        BrowserDialogs.showFileDetail(context, file);
                      }
                    },
                    onLongPress: () {
                      if (!state.isMultiSelect) {
                        onToggleSelection(file.fileId, isFolder: false);
                      }
                    },
                    onActionTap: () =>
                        BrowserDialogs.showFileDetail(context, file),
                  );
                  if (isCut) {
                    return Opacity(opacity: 0.45, child: tile);
                  }
                  return tile;
                },
                childCount: state.files.length,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
