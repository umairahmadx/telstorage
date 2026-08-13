import '../../../core/models/file_record.dart';
import '../screens/browser_screen.dart' show BrowserSortOption, BrowserGroupOption;

enum ClipboardMode { copy, move }

sealed class BrowserEvent {}

class LoadDirectory extends BrowserEvent {
  final String? folderId;
  final String? category;
  LoadDirectory({this.folderId, this.category});
}

class SearchQueryChanged extends BrowserEvent {
  final String query;
  SearchQueryChanged(this.query);
}

class SortOptionChanged extends BrowserEvent {
  final BrowserSortOption option;
  SortOptionChanged(this.option);
}

class GroupOptionChanged extends BrowserEvent {
  final BrowserGroupOption option;
  GroupOptionChanged(this.option);
}

class ToggleViewMode extends BrowserEvent {}

class ToggleItemSelection extends BrowserEvent {
  final String id;
  final bool isFolder;
  ToggleItemSelection(this.id, {required this.isFolder});
}

class ClearSelection extends BrowserEvent {}

class EnqueueDownload extends BrowserEvent {
  final FileRecord file;
  EnqueueDownload(this.file);
}

class EnqueueShare extends BrowserEvent {
  final FileRecord file;
  final String? password;
  final int? expiryDays;
  final String? vanitySlug;
  EnqueueShare(this.file, {this.password, this.expiryDays, this.vanitySlug});
}

class NavigateUp extends BrowserEvent {}

// Mutation Events
class CreateFolder extends BrowserEvent {
  final String name;
  CreateFolder(this.name);
}

class RenameFolder extends BrowserEvent {
  final String folderId;
  final String newName;
  RenameFolder(this.folderId, this.newName);
}

class DeleteFolder extends BrowserEvent {
  final String folderId;
  DeleteFolder(this.folderId);
}

class RenameFile extends BrowserEvent {
  final String fileId;
  final String newName;
  RenameFile(this.fileId, this.newName);
}

class MoveFile extends BrowserEvent {
  final String fileId;
  final String? targetFolderId;
  MoveFile(this.fileId, this.targetFolderId);
}

class CopyFile extends BrowserEvent {
  final String fileId;
  final String? targetFolderId;
  CopyFile(this.fileId, this.targetFolderId);
}

class DeleteFile extends BrowserEvent {
  final String fileId;
  DeleteFile(this.fileId);
}

class BatchDelete extends BrowserEvent {}

class BatchMove extends BrowserEvent {
  final String? targetFolderId;
  BatchMove(this.targetFolderId);
}

class BatchCopy extends BrowserEvent {
  final String? targetFolderId;
  BatchCopy(this.targetFolderId);
}

class SetClipboard extends BrowserEvent {
  final ClipboardMode mode;
  final Set<String> fileIds;
  final Set<String> folderIds;
  final String? sourceFolderId;

  SetClipboard({
    required this.mode,
    required this.fileIds,
    required this.folderIds,
    required this.sourceFolderId,
  });
}

class ClearClipboard extends BrowserEvent {}

class PasteClipboard extends BrowserEvent {
  final String? targetFolderId;
  PasteClipboard(this.targetFolderId);
}
