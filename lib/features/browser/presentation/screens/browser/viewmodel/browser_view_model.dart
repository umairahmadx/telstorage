/*
 * File: browser_view_model.dart
 * Description: Browser ViewModel (Bloc) managing directory navigation, file mutations, and clipboard operations.
 */

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/events/domain_event_bus.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';
import 'browser_event.dart';
import 'browser_filter_helper.dart';
import 'browser_state.dart';

export 'browser_event.dart';
export 'browser_state.dart';

/// ViewModel orchestrating file and folder navigation, search, and operations.
class BrowserBloc extends Bloc<BrowserEvent, BrowserState> {
  /// Internal repository reference.
  final StorageRepositoryContract _repository;

  /// Subscription to Hive folders database.
  StreamSubscription? _foldersSubscription;

  /// Subscription to Hive files database.
  StreamSubscription? _filesSubscription;

  /// Subscription to global domain event bus.
  StreamSubscription? _domainEventSubscription;

  /// Constructs BrowserBloc and registers event handlers.
  BrowserBloc([StorageRepositoryContract? repository])
      : _repository = repository ?? ServiceLocator.instance.storageRepository,
        super(BrowserState()) {
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

  /// Sets up reactive database and event bus listeners.
  void _initSubscriptions() {
    if (!ServiceLocator.instance.isInitialized) return;

    _foldersSubscription = ServiceLocator.instance.hive.foldersListenable.value
        .watch()
        .listen((_) {
      if (state.isInitialized) {
        add(LoadDirectory(
            folderId: state.currentFolderId, category: state.category));
      }
    });
    _filesSubscription = ServiceLocator.instance.hive.filesListenable.value
        .watch()
        .listen((_) {
      if (state.isInitialized) {
        add(LoadDirectory(
            folderId: state.currentFolderId, category: state.category));
      }
    });
    _domainEventSubscription =
        DomainEventBus.instance.on<FileUploadedEvent>().listen((_) {
      if (state.isInitialized) {
        add(LoadDirectory(
            folderId: state.currentFolderId, category: state.category));
      }
    });
  }

  /// Handles directory loading and offline synchronization check.
  Future<void> _onLoadDirectory(
      LoadDirectory event, Emitter<BrowserState> emit) async {
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
      emit(state.copyWith(
          isLoading: false, errorMessage: 'Initialization failed: $e'));
    }
  }

  /// Reloads, filters, and sorts contents in current directory.
  void _reloadContents(Emitter<BrowserState> emit, {required bool isOffline}) {
    final folderId = state.currentFolderId;
    final category = state.category;

    List<FolderRecord> rawFolders = [];
    List<FileRecord> rawFiles = [];

    if (category != null) {
      rawFiles = _repository.getFiles(folderId)
        ..retainWhere((f) => BrowserFilterHelper.matchesCategory(f, category));
      rawFolders = [];
    } else {
      rawFolders = _repository.getFolders(folderId);
      rawFiles = _repository.getFiles(folderId);
    }

    final q = state.searchQuery.toLowerCase();
    if (q.isNotEmpty) {
      rawFolders =
          rawFolders.where((f) => f.name.toLowerCase().contains(q)).toList();
      rawFiles =
          rawFiles.where((f) => f.name.toLowerCase().contains(q)).toList();
    }

    BrowserFilterHelper.sortItems(
        rawFolders, rawFiles, state.sortOption, state.sortAscending);

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

  /// Updates search query and refreshes.
  void _onSearchQueryChanged(
      SearchQueryChanged event, Emitter<BrowserState> emit) {
    emit(state.copyWith(searchQuery: event.query));
    _reloadContents(emit, isOffline: state.isOffline);
  }

  /// Updates sorting option and reloads.
  void _onSortOptionChanged(
      SortOptionChanged event, Emitter<BrowserState> emit) {
    final isSameOption = state.sortOption == event.option;
    final ascending = isSameOption ? !state.sortAscending : true;
    emit(state.copyWith(sortOption: event.option, sortAscending: ascending));
    _reloadContents(emit, isOffline: state.isOffline);
  }

  /// Updates grouping hierarchy.
  void _onGroupOptionChanged(
      GroupOptionChanged event, Emitter<BrowserState> emit) {
    emit(state.copyWith(groupOption: event.option));
  }

  /// Toggles view mode (grid vs list).
  void _onToggleViewMode(ToggleViewMode event, Emitter<BrowserState> emit) {
    emit(state.copyWith(isGridView: !state.isGridView));
  }

  /// Toggles selection of an item.
  void _onToggleItemSelection(
      ToggleItemSelection event, Emitter<BrowserState> emit) {
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

  /// Clears active multi-selections.
  void _onClearSelection(ClearSelection event, Emitter<BrowserState> emit) {
    emit(state.copyWith(
      selectedFolderIds: {},
      selectedFileIds: {},
    ));
  }

  /// Enqueues download task.
  Future<void> _onEnqueueDownload(
      EnqueueDownload event, Emitter<BrowserState> emit) async {
    try {
      await _repository.enqueueDownload(event.file);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Download failed to start: $e'));
    }
  }

  /// Enqueues web share task.
  Future<void> _onEnqueueShare(
      EnqueueShare event, Emitter<BrowserState> emit) async {
    try {
      await _repository.enqueueWebShare(
        event.file,
        password: event.password,
        expiryDays: event.expiryDays,
        vanitySlug: event.vanitySlug,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Sharing failed to start: $e'));
    }
  }

  /// Navigates up to parent directory.
  void _onNavigateUp(NavigateUp event, Emitter<BrowserState> emit) {
    if (state.category != null) {
      add(LoadDirectory(folderId: state.currentFolderId));
    } else if (state.currentFolderId != null) {
      final folder = _repository.getFolder(state.currentFolderId!);
      add(LoadDirectory(folderId: folder?.parentId));
    }
  }

  /// Handles creation of a folder.
  Future<void> _onCreateFolder(
      CreateFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final res = await _repository.createFolder(event.name,
        parentId: state.currentFolderId);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) =>
          emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
  }

  /// Handles folder rename.
  Future<void> _onRenameFolder(
      RenameFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final res = await _repository.renameFolder(event.folderId, event.newName);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) =>
          emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
  }

  /// Handles folder deletion.
  Future<void> _onDeleteFolder(
      DeleteFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final res = await _repository.deleteFolder(event.folderId);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) =>
          emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
  }

  /// Handles file rename.
  Future<void> _onRenameFile(
      RenameFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final res = await _repository.renameFile(event.fileId, event.newName);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) =>
          emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
  }

  /// Handles single file move.
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

  /// Handles single file copy.
  Future<void> _onCopyFile(CopyFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final res = await _repository.copyFile(event.fileId, event.targetFolderId);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) =>
          emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
  }

  /// Handles single file deletion.
  Future<void> _onDeleteFile(
      DeleteFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final res = await _repository.deleteFile(event.fileId);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) =>
          emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
  }

  /// Handles batch deletion of items.
  Future<void> _onBatchDelete(
      BatchDelete event, Emitter<BrowserState> emit) async {
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

  /// Handles batch move of items.
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

  /// Handles batch copy of items.
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

  /// Sets clipboard contents for cut/copy.
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

  /// Clears clipboard.
  void _onClearClipboard(ClearClipboard event, Emitter<BrowserState> emit) {
    emit(state.copyWith(clearClipboard: true));
  }

  /// Pastes clipboard contents into destination folder.
  Future<void> _onPasteClipboard(
      PasteClipboard event, Emitter<BrowserState> emit) async {
    if (!state.hasClipboard) return;

    final targetFolderId = event.targetFolderId;
    final mode = state.clipboardMode;

    if (targetFolderId == state.clipboardSourceFolderId &&
        mode == ClipboardMode.move) {
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
    _domainEventSubscription?.cancel();
    return super.close();
  }
}

/// Type alias aligning BrowserBloc with MVVM nomenclature.
typedef BrowserViewModel = BrowserBloc;
