/// File: browser_event.dart
/// Description: Event definitions and clipboard modes for the file browser feature.
library;

import '../../../../../../core/models/file_record.dart';

/// Supported sorting options in the file browser.
enum BrowserSortOption {
  /// Sort alphabetically by name.
  name,

  /// Sort chronologically by upload / creation date.
  date,

  /// Sort by file size.
  size,
}

/// Grouping hierarchy options.
enum BrowserGroupOption {
  /// Always pin folders before files.
  foldersFirst,

  /// Mix folders and files together.
  mixed,
}

/// Clipboard operation modes for cut/copy/paste.
enum ClipboardMode {
  /// Copy items to destination.
  copy,

  /// Move items to destination.
  move,
}

/// Base abstract event for the file browser.
sealed class BrowserEvent {}

/// Loads directory contents by folder ID or category filter.
class LoadDirectory extends BrowserEvent {
  /// Target folder identifier (null for root).
  final String? folderId;

  /// Optional media category filter ('images', 'videos', 'docs', etc.).
  final String? category;

  /// Constructs a LoadDirectory event.
  LoadDirectory({this.folderId, this.category});
}

/// Updates the current search filter query.
class SearchQueryChanged extends BrowserEvent {
  /// Search query string.
  final String query;

  /// Constructs SearchQueryChanged event.
  SearchQueryChanged(this.query);
}

/// Updates active sort criteria.
class SortOptionChanged extends BrowserEvent {
  /// Desired sort option.
  final BrowserSortOption option;

  /// Constructs SortOptionChanged event.
  SortOptionChanged(this.option);
}

/// Updates folder/file grouping mode.
class GroupOptionChanged extends BrowserEvent {
  /// Desired group option.
  final BrowserGroupOption option;

  /// Constructs GroupOptionChanged event.
  GroupOptionChanged(this.option);
}

/// Toggles between list view and grid view.
class ToggleViewMode extends BrowserEvent {}

/// Toggles selection state of a folder or file.
class ToggleItemSelection extends BrowserEvent {
  /// Unique identifier of item.
  final String id;

  /// Flag indicating if item is a folder.
  final bool isFolder;

  /// Constructs ToggleItemSelection event.
  ToggleItemSelection(this.id, {required this.isFolder});
}

/// Clears all actively selected items.
class ClearSelection extends BrowserEvent {}

/// Enqueues download task for specified file.
class EnqueueDownload extends BrowserEvent {
  /// File to download.
  final FileRecord file;

  /// Constructs EnqueueDownload event.
  EnqueueDownload(this.file);
}

/// Enqueues web share link creation.
class EnqueueShare extends BrowserEvent {
  /// File to share.
  final FileRecord file;

  /// Optional link password.
  final String? password;

  /// Expiry duration in days.
  final int? expiryDays;

  /// Custom vanity slug.
  final String? vanitySlug;

  /// Constructs EnqueueShare event.
  EnqueueShare(this.file, {this.password, this.expiryDays, this.vanitySlug});
}

/// Navigates up to parent directory.
class NavigateUp extends BrowserEvent {}

/// Creates a new subfolder in current directory.
class CreateFolder extends BrowserEvent {
  /// Folder name.
  final String name;

  /// Constructs CreateFolder event.
  CreateFolder(this.name);
}

/// Renames an existing folder.
class RenameFolder extends BrowserEvent {
  /// Target folder ID.
  final String folderId;

  /// New name.
  final String newName;

  /// Constructs RenameFolder event.
  RenameFolder(this.folderId, this.newName);
}

/// Deletes a folder by ID.
class DeleteFolder extends BrowserEvent {
  /// Folder ID to remove.
  final String folderId;

  /// Constructs DeleteFolder event.
  DeleteFolder(this.folderId);
}

/// Renames a file.
class RenameFile extends BrowserEvent {
  /// File identifier.
  final String fileId;

  /// New file name.
  final String newName;

  /// Constructs RenameFile event.
  RenameFile(this.fileId, this.newName);
}

/// Moves a file to another folder.
class MoveFile extends BrowserEvent {
  /// File ID.
  final String fileId;

  /// Destination folder ID.
  final String? targetFolderId;

  /// Constructs MoveFile event.
  MoveFile(this.fileId, this.targetFolderId);
}

/// Copies a file to another folder.
class CopyFile extends BrowserEvent {
  /// File ID.
  final String fileId;

  /// Destination folder ID.
  final String? targetFolderId;

  /// Constructs CopyFile event.
  CopyFile(this.fileId, this.targetFolderId);
}

/// Deletes a file.
class DeleteFile extends BrowserEvent {
  /// File identifier to delete.
  final String fileId;

  /// Constructs DeleteFile event.
  DeleteFile(this.fileId);
}

/// Batch deletes all currently selected files and folders.
class BatchDelete extends BrowserEvent {}

/// Batch moves all currently selected items to a target folder.
class BatchMove extends BrowserEvent {
  /// Destination folder ID.
  final String? targetFolderId;

  /// Constructs BatchMove event.
  BatchMove(this.targetFolderId);
}

/// Batch copies all selected items to a target folder.
class BatchCopy extends BrowserEvent {
  /// Destination folder ID.
  final String? targetFolderId;

  /// Constructs BatchCopy event.
  BatchCopy(this.targetFolderId);
}

/// Sets items into clipboard buffer for copy or move.
class SetClipboard extends BrowserEvent {
  /// Operation mode (copy or move).
  final ClipboardMode mode;

  /// Set of selected file IDs.
  final Set<String> fileIds;

  /// Set of selected folder IDs.
  final Set<String> folderIds;

  /// Origin folder ID.
  final String? sourceFolderId;

  /// Constructs SetClipboard event.
  SetClipboard({
    required this.mode,
    required this.fileIds,
    required this.folderIds,
    required this.sourceFolderId,
  });
}

/// Clears active clipboard buffer.
class ClearClipboard extends BrowserEvent {}

/// Pastes clipboard contents into destination folder.
class PasteClipboard extends BrowserEvent {
  /// Target folder ID.
  final String? targetFolderId;

  /// Constructs PasteClipboard event.
  PasteClipboard(this.targetFolderId);
}
