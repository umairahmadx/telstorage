import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/folder_record.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/connectivity.dart';
import '../../storage/data/repositories/storage_repository.dart';
import '../screens/browser_screen.dart' show BrowserSortOption, BrowserGroupOption;

// ── Events ────────────────────────────────────────────────────────────────────

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
  EnqueueShare(this.file, {this.password, this.expiryDays});
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

enum ClipboardMode { copy, move }

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

// ── States ────────────────────────────────────────────────────────────────────

class BrowserState {
  final bool isLoading;
  final bool isInitialized;
  final String? currentFolderId;
  final String? category;
  final List<FolderRecord> folders;
  final List<FileRecord> files;
  final Map<String, int> folderItemCounts;
  final String searchQuery;
  final BrowserSortOption sortOption;
  final bool sortAscending;
  final BrowserGroupOption groupOption;
  final bool isGridView;
  final Set<String> selectedFolderIds;
  final Set<String> selectedFileIds;
  final ClipboardMode? clipboardMode;
  final Set<String> clipboardFileIds;
  final Set<String> clipboardFolderIds;
  final String? clipboardSourceFolderId;
  final String? errorMessage;
  final bool isOffline;
  final int pendingActionsCount;

  BrowserState({
    this.isLoading = false,
    this.isInitialized = false,
    this.currentFolderId,
    this.category,
    this.folders = const [],
    this.files = const [],
    this.folderItemCounts = const {},
    this.searchQuery = '',
    this.sortOption = BrowserSortOption.name,
    this.sortAscending = true,
    this.groupOption = BrowserGroupOption.foldersFirst,
    this.isGridView = false,
    this.selectedFolderIds = const {},
    this.selectedFileIds = const {},
    this.clipboardMode,
    this.clipboardFileIds = const {},
    this.clipboardFolderIds = const {},
    this.clipboardSourceFolderId,
    this.errorMessage,
    this.isOffline = false,
    this.pendingActionsCount = 0,
  });

  bool get isMultiSelect => selectedFolderIds.isNotEmpty || selectedFileIds.isNotEmpty;
  bool get hasClipboard => clipboardFileIds.isNotEmpty || clipboardFolderIds.isNotEmpty;

  BrowserState copyWith({
    bool? isLoading,
    bool? isInitialized,
    String? currentFolderId,
    bool clearFolderId = false,
    String? category,
    bool clearCategory = false,
    List<FolderRecord>? folders,
    List<FileRecord>? files,
    Map<String, int>? folderItemCounts,
    String? searchQuery,
    BrowserSortOption? sortOption,
    bool? sortAscending,
    BrowserGroupOption? groupOption,
    bool? isGridView,
    Set<String>? selectedFolderIds,
    Set<String>? selectedFileIds,
    ClipboardMode? clipboardMode,
    Set<String>? clipboardFileIds,
    Set<String>? clipboardFolderIds,
    String? clipboardSourceFolderId,
    bool clearClipboard = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isOffline,
    int? pendingActionsCount,
  }) {
    return BrowserState(
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      currentFolderId: clearFolderId ? null : (currentFolderId ?? this.currentFolderId),
      category: clearCategory ? null : (category ?? this.category),
      folders: folders ?? this.folders,
      files: files ?? this.files,
      folderItemCounts: folderItemCounts ?? this.folderItemCounts,
      searchQuery: searchQuery ?? this.searchQuery,
      sortOption: sortOption ?? this.sortOption,
      sortAscending: sortAscending ?? this.sortAscending,
      groupOption: groupOption ?? this.groupOption,
      isGridView: isGridView ?? this.isGridView,
      selectedFolderIds: selectedFolderIds ?? this.selectedFolderIds,
      selectedFileIds: selectedFileIds ?? this.selectedFileIds,
      clipboardMode: clearClipboard ? null : (clipboardMode ?? this.clipboardMode),
      clipboardFileIds: clearClipboard ? const {} : (clipboardFileIds ?? this.clipboardFileIds),
      clipboardFolderIds: clearClipboard ? const {} : (clipboardFolderIds ?? this.clipboardFolderIds),
      clipboardSourceFolderId: clearClipboard ? null : (clipboardSourceFolderId ?? this.clipboardSourceFolderId),
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isOffline: isOffline ?? this.isOffline,
      pendingActionsCount: pendingActionsCount ?? this.pendingActionsCount,
    );
  }
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

class BrowserBloc extends Bloc<BrowserEvent, BrowserState> {
  final StorageRepository _repository = ServiceLocator.instance.storageRepository;
  StreamSubscription? _foldersSubscription;
  StreamSubscription? _filesSubscription;

  BrowserBloc() : super(BrowserState()) {
    on<LoadDirectory>(_onLoadDirectory);
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<SortOptionChanged>(_onSortOptionChanged);
    on<GroupOptionChanged>(_onGroupOptionChanged);
    on<ToggleViewMode>(_onToggleViewMode);
    on<ToggleItemSelection>(_onToggleItemSelection);
    on<ClearSelection>(_onClearSelection);
    on<EnqueueDownload>(_onEnqueueDownload);
    on<EnqueueShare>(_onEnqueueShare);
    on<NavigateUp>(_onNavigateUp);
    
    // Mutation Handlers
    on<CreateFolder>(_onCreateFolder);
    on<RenameFolder>(_onRenameFolder);
    on<DeleteFolder>(_onDeleteFolder);
    on<RenameFile>(_onRenameFile);
    on<MoveFile>(_onMoveFile);
    on<CopyFile>(_onCopyFile);
    on<DeleteFile>(_onDeleteFile);
    on<BatchDelete>(_onBatchDelete);
    on<BatchMove>(_onBatchMove);
    on<BatchCopy>(_onBatchCopy);
    on<SetClipboard>(_onSetClipboard);
    on<ClearClipboard>(_onClearClipboard);
    on<PasteClipboard>(_onPasteClipboard);

    _initSubscriptions();
  }

  void _initSubscriptions() {
    _foldersSubscription = ServiceLocator.instance.hive.foldersListenable.value.watch().listen((_) {
      if (state.isInitialized) {
         add(LoadDirectory(folderId: state.currentFolderId, category: state.category));
      }
    });
    _filesSubscription = ServiceLocator.instance.hive.filesListenable.value.watch().listen((_) {
      if (state.isInitialized) {
        add(LoadDirectory(folderId: state.currentFolderId, category: state.category));
      }
    });
  }

  Future<void> _onLoadDirectory(LoadDirectory event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(
      isLoading: true,
      currentFolderId: event.folderId,
      clearFolderId: event.folderId == null,
      category: event.category,
      clearCategory: event.category == null,
    ));

    try {
      if (!ServiceLocator.instance.isInitialized) {
        await ServiceLocator.instance.init();
      }

      final isOffline = !await Connectivity.hasConnection();
      _reloadContents(emit, isOffline: isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: 'Initialization failed: $e'));
    }
  }

  void _reloadContents(Emitter<BrowserState> emit, {required bool isOffline}) {
    final folderId = state.currentFolderId;
    final category = state.category;

    List<FolderRecord> rawFolders = [];
    List<FileRecord> rawFiles = [];

    if (category != null) {
      rawFiles = _repository.getFiles(folderId)
        ..retainWhere((f) => _matchesCategory(f, category));
      // Usually don't show folders in filtered category view
      rawFolders = [];
    } else {
      rawFolders = _repository.getFolders(folderId);
      rawFiles = _repository.getFiles(folderId);
    }

    // Apply search filter
    final q = state.searchQuery.toLowerCase();
    if (q.isNotEmpty) {
      rawFolders = rawFolders.where((f) => f.name.toLowerCase().contains(q)).toList();
      rawFiles = rawFiles.where((f) => f.name.toLowerCase().contains(q)).toList();
    }

    // Apply sorting
    _sortItems(rawFolders, rawFiles, state.sortOption, state.sortAscending);

    // Calculate folder item counts
    final Map<String, int> counts = {};
    for (final f in rawFolders) {
      counts[f.id] = _repository.getFilesInFolderCount(f.id);
    }

    emit(state.copyWith(
      isLoading: false,
      isInitialized: true,
      folders: rawFolders,
      files: rawFiles,
      folderItemCounts: counts,
      isOffline: isOffline,
      pendingActionsCount: ServiceLocator.instance.syncQueue.pendingCount,
    ));
  }

  void _sortItems(List<FolderRecord> folders, List<FileRecord> files, BrowserSortOption option, bool ascending) {
    if (option == BrowserSortOption.name) {
      folders.sort((a, b) => ascending
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
      files.sort((a, b) => ascending
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    } else if (option == BrowserSortOption.date) {
      folders.sort((a, b) => ascending
          ? a.createdAt.compareTo(b.createdAt)
          : b.createdAt.compareTo(a.createdAt));
      files.sort((a, b) => ascending
          ? a.uploadedAt.compareTo(b.uploadedAt)
          : b.uploadedAt.compareTo(a.uploadedAt));
    } else if (option == BrowserSortOption.size) {
      // Folders have size 0
      files.sort((a, b) => ascending
          ? a.sizeMb.compareTo(b.sizeMb)
          : b.sizeMb.compareTo(a.sizeMb));
    }
  }

  bool _matchesCategory(FileRecord file, String category) {
    final mimeType = file.mimeType.toLowerCase();
    switch (category) {
      case 'images':
        return mimeType.startsWith('image/');
      case 'videos':
        return mimeType.startsWith('video/');
      case 'docs':
        return mimeType == 'application/pdf';
      case 'others':
        return !mimeType.startsWith('image/') &&
            !mimeType.startsWith('video/') &&
            mimeType != 'application/pdf';
      default:
        return true;
    }
  }

  void _onSearchQueryChanged(SearchQueryChanged event, Emitter<BrowserState> emit) {
    emit(state.copyWith(searchQuery: event.query));
    _reloadContents(emit, isOffline: state.isOffline);
  }

  void _onSortOptionChanged(SortOptionChanged event, Emitter<BrowserState> emit) {
    final isSameOption = state.sortOption == event.option;
    final ascending = isSameOption ? !state.sortAscending : true;
    emit(state.copyWith(sortOption: event.option, sortAscending: ascending));
    _reloadContents(emit, isOffline: state.isOffline);
  }

  void _onGroupOptionChanged(GroupOptionChanged event, Emitter<BrowserState> emit) {
    emit(state.copyWith(groupOption: event.option));
  }

  void _onToggleViewMode(ToggleViewMode event, Emitter<BrowserState> emit) {
    emit(state.copyWith(isGridView: !state.isGridView));
  }

  void _onToggleItemSelection(ToggleItemSelection event, Emitter<BrowserState> emit) {
    final selectedFolders = Set<String>.from(state.selectedFolderIds);
    final selectedFiles = Set<String>.from(state.selectedFileIds);

    if (event.isFolder) {
      if (selectedFolders.contains(event.id)) {
        selectedFolders.remove(event.id);
      } else {
        selectedFolders.add(event.id);
      }
    } else {
      if (selectedFiles.contains(event.id)) {
        selectedFiles.remove(event.id);
      } else {
        selectedFiles.add(event.id);
      }
    }

    emit(state.copyWith(
      selectedFolderIds: selectedFolders,
      selectedFileIds: selectedFiles,
    ));
  }

  void _onClearSelection(ClearSelection event, Emitter<BrowserState> emit) {
    emit(state.copyWith(
      selectedFolderIds: {},
      selectedFileIds: {},
    ));
  }

  Future<void> _onEnqueueDownload(EnqueueDownload event, Emitter<BrowserState> emit) async {
    try {
      await _repository.enqueueDownload(event.file);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Download failed to start: $e'));
    }
  }

  Future<void> _onEnqueueShare(EnqueueShare event, Emitter<BrowserState> emit) async {
    try {
      await _repository.enqueueWebShare(event.file, 
          password: event.password, expiryDays: event.expiryDays);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Sharing failed to start: $e'));
    }
  }

  void _onNavigateUp(NavigateUp event, Emitter<BrowserState> emit) {
    if (state.category != null) {
      add(LoadDirectory(folderId: state.currentFolderId));
    } else if (state.currentFolderId != null) {
      final folder = _repository.getFolder(state.currentFolderId!);
      add(LoadDirectory(folderId: folder?.parentId));
    }
  }

  // ── Mutation Handlers ────────────────────────────────────────────────────────

  Future<void> _onCreateFolder(CreateFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _repository.createFolder(event.name, parentId: state.currentFolderId);
      // Trigger sync queue in background
      ServiceLocator.instance.syncQueue.processQueue();
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onRenameFolder(RenameFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _repository.renameFolder(event.folderId, event.newName);
      ServiceLocator.instance.syncQueue.processQueue();
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onDeleteFolder(DeleteFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _repository.deleteFolder(event.folderId);
      ServiceLocator.instance.syncQueue.processQueue();
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onRenameFile(RenameFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _repository.renameFile(event.fileId, event.newName);
      ServiceLocator.instance.syncQueue.processQueue();
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onMoveFile(MoveFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _repository.moveFile(event.fileId, event.targetFolderId);
      ServiceLocator.instance.syncQueue.processQueue();
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onCopyFile(CopyFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _repository.copyFile(event.fileId, event.targetFolderId);
      ServiceLocator.instance.syncQueue.processQueue();
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onDeleteFile(DeleteFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await _repository.deleteFile(event.fileId);
      ServiceLocator.instance.syncQueue.processQueue();
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onBatchDelete(BatchDelete event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      for (final folderId in List.from(state.selectedFolderIds)) {
        await _repository.deleteFolder(folderId);
      }
      for (final fileId in List.from(state.selectedFileIds)) {
        await _repository.deleteFile(fileId);
      }
      ServiceLocator.instance.syncQueue.processQueue();
      emit(state.copyWith(selectedFolderIds: {}, selectedFileIds: {}));
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onBatchMove(BatchMove event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      for (final folderId in List.from(state.selectedFolderIds)) {
        await _repository.moveFolder(folderId, event.targetFolderId);
      }
      for (final fileId in List.from(state.selectedFileIds)) {
        await _repository.moveFile(fileId, event.targetFolderId);
      }
      ServiceLocator.instance.syncQueue.processQueue();
      emit(state.copyWith(selectedFolderIds: {}, selectedFileIds: {}));
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onBatchCopy(BatchCopy event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      for (final folderId in List.from(state.selectedFolderIds)) {
        await _repository.copyFolder(folderId, event.targetFolderId);
      }
      for (final fileId in List.from(state.selectedFileIds)) {
        await _repository.copyFile(fileId, event.targetFolderId);
      }
      ServiceLocator.instance.syncQueue.processQueue();
      emit(state.copyWith(selectedFolderIds: {}, selectedFileIds: {}));
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onSetClipboard(SetClipboard event, Emitter<BrowserState> emit) {
    emit(state.copyWith(
      clipboardMode: event.mode,
      clipboardFileIds: event.fileIds,
      clipboardFolderIds: event.folderIds,
      clipboardSourceFolderId: event.sourceFolderId,
      selectedFolderIds: {},
      selectedFileIds: {},
    ));
  }

  void _onClearClipboard(ClearClipboard event, Emitter<BrowserState> emit) {
    emit(state.copyWith(clearClipboard: true));
  }

  Future<void> _onPasteClipboard(PasteClipboard event, Emitter<BrowserState> emit) async {
    if (!state.hasClipboard) return;

    final targetFolderId = event.targetFolderId;
    final mode = state.clipboardMode;

    if (targetFolderId == state.clipboardSourceFolderId && mode == ClipboardMode.move) {
      emit(state.copyWith(
        clearClipboard: true,
        errorMessage: 'Source and destination folders are the same.',
      ));
      return;
    }

    emit(state.copyWith(isLoading: true));

    try {
      if (mode == ClipboardMode.move) {
        for (final folderId in List.from(state.clipboardFolderIds)) {
          await _repository.moveFolder(folderId, targetFolderId);
        }
        for (final fileId in List.from(state.clipboardFileIds)) {
          await _repository.moveFile(fileId, targetFolderId);
        }
      } else if (mode == ClipboardMode.copy) {
        for (final folderId in List.from(state.clipboardFolderIds)) {
          await _repository.copyFolder(folderId, targetFolderId);
        }
        for (final fileId in List.from(state.clipboardFileIds)) {
          await _repository.copyFile(fileId, targetFolderId);
        }
      }

      ServiceLocator.instance.syncQueue.processQueue();
      emit(state.copyWith(clearClipboard: true));
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  @override
  Future<void> close() {
    _foldersSubscription?.cancel();
    _filesSubscription?.cancel();
    return super.close();
  }
}
