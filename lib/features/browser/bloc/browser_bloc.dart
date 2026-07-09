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

class DeleteFile extends BrowserEvent {
  final String fileId;
  DeleteFile(this.fileId);
}

class BatchDelete extends BrowserEvent {}

class BatchMove extends BrowserEvent {
  final String? targetFolderId;
  BatchMove(this.targetFolderId);
}

// ── States ────────────────────────────────────────────────────────────────────

class BrowserState {
  final bool isLoading;
  final String? currentFolderId;
  final String? category;
  final List<FolderRecord> folders;
  final List<FileRecord> files;
  final String searchQuery;
  final BrowserSortOption sortOption;
  final bool sortAscending;
  final BrowserGroupOption groupOption;
  final bool isGridView;
  final Set<String> selectedFolderIds;
  final Set<String> selectedFileIds;
  final String? errorMessage;
  final bool isOffline;
  final int pendingActionsCount;

  BrowserState({
    this.isLoading = false,
    this.currentFolderId,
    this.category,
    this.folders = const [],
    this.files = const [],
    this.searchQuery = '',
    this.sortOption = BrowserSortOption.name,
    this.sortAscending = true,
    this.groupOption = BrowserGroupOption.foldersFirst,
    this.isGridView = false,
    this.selectedFolderIds = const {},
    this.selectedFileIds = const {},
    this.errorMessage,
    this.isOffline = false,
    this.pendingActionsCount = 0,
  });

  bool get isMultiSelect => selectedFolderIds.isNotEmpty || selectedFileIds.isNotEmpty;

  BrowserState copyWith({
    bool? isLoading,
    String? currentFolderId,
    bool clearFolderId = false,
    String? category,
    bool clearCategory = false,
    List<FolderRecord>? folders,
    List<FileRecord>? files,
    String? searchQuery,
    BrowserSortOption? sortOption,
    bool? sortAscending,
    BrowserGroupOption? groupOption,
    bool? isGridView,
    Set<String>? selectedFolderIds,
    Set<String>? selectedFileIds,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isOffline,
    int? pendingActionsCount,
  }) {
    return BrowserState(
      isLoading: isLoading ?? this.isLoading,
      currentFolderId: clearFolderId ? null : (currentFolderId ?? this.currentFolderId),
      category: clearCategory ? null : (category ?? this.category),
      folders: folders ?? this.folders,
      files: files ?? this.files,
      searchQuery: searchQuery ?? this.searchQuery,
      sortOption: sortOption ?? this.sortOption,
      sortAscending: sortAscending ?? this.sortAscending,
      groupOption: groupOption ?? this.groupOption,
      isGridView: isGridView ?? this.isGridView,
      selectedFolderIds: selectedFolderIds ?? this.selectedFolderIds,
      selectedFileIds: selectedFileIds ?? this.selectedFileIds,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isOffline: isOffline ?? this.isOffline,
      pendingActionsCount: pendingActionsCount ?? this.pendingActionsCount,
    );
  }
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

class BrowserBloc extends Bloc<BrowserEvent, BrowserState> {
  final StorageRepository _repository = ServiceLocator.instance.storageRepository;
  late final StreamSubscription _foldersSubscription;
  late final StreamSubscription _filesSubscription;

  BrowserBloc() : super(BrowserState()) {
    _foldersSubscription = ServiceLocator.instance.hive.foldersListenable.value.watch().listen((_) {
      add(LoadDirectory(folderId: state.currentFolderId, category: state.category));
    });
    _filesSubscription = ServiceLocator.instance.hive.filesListenable.value.watch().listen((_) {
      add(LoadDirectory(folderId: state.currentFolderId, category: state.category));
    });
    on<LoadDirectory>(_onLoadDirectory);
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<SortOptionChanged>(_onSortOptionChanged);
    on<GroupOptionChanged>(_onGroupOptionChanged);
    on<ToggleViewMode>(_onToggleViewMode);
    on<ToggleItemSelection>(_onToggleItemSelection);
    on<ClearSelection>(_onClearSelection);
    
    // Mutation Handlers
    on<CreateFolder>(_onCreateFolder);
    on<RenameFolder>(_onRenameFolder);
    on<DeleteFolder>(_onDeleteFolder);
    on<RenameFile>(_onRenameFile);
    on<MoveFile>(_onMoveFile);
    on<DeleteFile>(_onDeleteFile);
    on<BatchDelete>(_onBatchDelete);
    on<BatchMove>(_onBatchMove);
  }

  Future<void> _onLoadDirectory(LoadDirectory event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(
      isLoading: true,
      currentFolderId: event.folderId,
      clearFolderId: event.folderId == null,
      category: event.category,
      clearCategory: event.category == null,
    ));

    final isOffline = !await Connectivity.hasConnection();

    // Load from local Hive cache via Repository (offline-first)
    _reloadContents(emit, isOffline: isOffline);
  }

  void _reloadContents(Emitter<BrowserState> emit, {required bool isOffline}) {
    final folderId = state.currentFolderId;
    final category = state.category;

    List<FolderRecord> rawFolders = [];
    List<FileRecord> rawFiles = [];

    if (category != null) {
      rawFiles = _repository.getFiles(null) // Fetch all to filter by category
        ..addAll(_repository.getFiles('')) // Just in case
        ..retainWhere((f) => _matchesCategory(f, category));
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

    emit(state.copyWith(
      isLoading: false,
      folders: rawFolders,
      files: rawFiles,
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

  @override
  Future<void> close() {
    _foldersSubscription.cancel();
    _filesSubscription.cancel();
    return super.close();
  }
}
