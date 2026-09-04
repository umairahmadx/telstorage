/*
 * File: browser_view_model.dart
 * Description: Browser ViewModel (Bloc) managing directory navigation, file mutations, and clipboard operations.
 */

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/events/domain_event_bus.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';
import 'browser_batch_helper.dart';
import 'browser_event.dart';
import 'browser_filter_helper.dart';
import 'browser_mutation_helper.dart';
import 'browser_partition_helper.dart';
import 'browser_state.dart';

export 'browser_event.dart';
export 'browser_state.dart';

/// ViewModel orchestrating file and folder navigation, search, and operations.
class BrowserBloc extends Bloc<BrowserEvent, BrowserState> {
  final StorageRepositoryContract _repository;
  final bool _isCustomRepo;
  StreamSubscription? _foldersSubscription;
  StreamSubscription? _filesSubscription;
  StreamSubscription? _domainEventSubscription;

  /// Constructs BrowserBloc and registers event handlers.
  BrowserBloc([StorageRepositoryContract? repository])
      : _repository = repository ?? ServiceLocator.instance.storageRepository,
        _isCustomRepo = repository != null,
        super(BrowserState()) {
    on<LoadDirectory>(_onLoadDirectory);
    on<LocalContentsChanged>(_onLocalContentsChanged);
    on<SearchQueryChanged>(_onSearchQueryChanged);
    on<SortOptionChanged>(_onSortOptionChanged);
    on<GroupOptionChanged>(_onGroupOptionChanged);
    on<ToggleViewMode>(_onToggleViewMode);
    on<ToggleItemSelection>(_onToggleItemSelection);
    on<ToggleSelectAll>(_onToggleSelectAll);
    on<ClearSelection>(_onClearSelection);
    on<EnqueueDownload>(_onEnqueueDownload);
    on<EnqueueShare>(_onEnqueueShare);
    on<BatchDownload>(_onBatchDownload);
    on<DownloadFolder>(_onDownloadFolder);
    on<ExportFolderAsZip>(_onExportFolderAsZip);
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
    if (_isCustomRepo || !ServiceLocator.instance.isInitialized) return;

    _foldersSubscription = ServiceLocator.instance.hive.foldersListenable.value
        .watch()
        .listen((_) => add(const LocalContentsChanged()));
    _filesSubscription = ServiceLocator.instance.hive.filesListenable.value
        .watch()
        .listen((_) => add(const LocalContentsChanged()));
    _domainEventSubscription = DomainEventBus.instance
        .on<FileUploadedEvent>()
        .listen((_) => add(const LocalContentsChanged()));
  }

  void _onLocalContentsChanged(
      LocalContentsChanged event, Emitter<BrowserState> emit) {
    if (state.isInitialized) {
      _reloadContents(emit, isOffline: state.isOffline);
    }
  }

  /// Handles directory loading and offline synchronization check.
  Future<void> _onLoadDirectory(
      LoadDirectory event, Emitter<BrowserState> emit) async {
    final isFolderChange = event.folderId != state.currentFolderId;
    final activeQuery = isFolderChange ? '' : state.searchQuery;
    final local = BrowserFilterHelper.loadAndFilterContents(
      repository: _repository,
      folderId: event.folderId,
      category: event.category,
      searchQuery: activeQuery,
      sortOption: state.sortOption,
      sortAscending: state.sortAscending,
    );

    emit(state.copyWith(
      isLoading: true,
      currentFolderId: event.folderId,
      clearFolderId: event.folderId == null,
      category: event.category,
      clearCategory: event.category == null,
      searchQuery: activeQuery,
      folders: local.folders,
      files: local.files,
      folderItemCounts: local.folderItemCounts,
      clearErrorMessage: true,
    ));

    try {
      if (_isCustomRepo) {
        _reloadContents(emit, isOffline: false);
        return;
      }

      if (!ServiceLocator.instance.isInitialized) {
        await ServiceLocator.instance.init();
      }

      final isOffline = !await Connectivity.hasConnection();
      final isReady =
          await BrowserPartitionHelper.ensureDirectoryPartitionReady(
        folderId: event.folderId,
        isOffline: isOffline,
      );

      if (!isReady) {
        emit(state.copyWith(
          isLoading: false,
          isInitialized: true,
          isOffline: true,
          folders: [],
          files: [],
          errorMessage: 'No internet connection',
        ));
        return;
      }

      _reloadContents(emit, isOffline: isOffline);
    } catch (e) {
      emit(state.copyWith(
          isLoading: false, errorMessage: 'Initialization failed: $e'));
    }
  }

  /// Reloads, filters, and sorts contents in current directory.
  void _reloadContents(Emitter<BrowserState> emit, {required bool isOffline}) {
    final result = BrowserFilterHelper.loadAndFilterContents(
      repository: _repository,
      folderId: state.currentFolderId,
      category: state.category,
      searchQuery: state.searchQuery,
      sortOption: state.sortOption,
      sortAscending: state.sortAscending,
    );

    emit(state.copyWith(
      isLoading: false,
      isInitialized: true,
      folders: result.folders,
      files: result.files,
      folderItemCounts: result.folderItemCounts,
      isOffline: isOffline,
      pendingActionsCount: ServiceLocator.instance.isInitialized
          ? ServiceLocator.instance.syncQueue.pendingCount
          : 0,
    ));
  }

  void _onSearchQueryChanged(
      SearchQueryChanged event, Emitter<BrowserState> emit) {
    emit(state.copyWith(searchQuery: event.query));
    _reloadContents(emit, isOffline: state.isOffline);
  }

  void _onSortOptionChanged(
      SortOptionChanged event, Emitter<BrowserState> emit) {
    final isSameOption = state.sortOption == event.option;
    final ascending = isSameOption ? !state.sortAscending : true;
    emit(state.copyWith(sortOption: event.option, sortAscending: ascending));
    _reloadContents(emit, isOffline: state.isOffline);
  }

  void _onGroupOptionChanged(
          GroupOptionChanged event, Emitter<BrowserState> emit) =>
      emit(state.copyWith(groupOption: event.option));

  void _onToggleViewMode(ToggleViewMode event, Emitter<BrowserState> emit) =>
      emit(state.copyWith(isGridView: !state.isGridView));

  void _onToggleItemSelection(
      ToggleItemSelection event, Emitter<BrowserState> emit) {
    final selectedFolders = Set<String>.from(state.selectedFolderIds);
    final selectedFiles = Set<String>.from(state.selectedFileIds);

    if (event.isFolder) {
      if (!selectedFolders.remove(event.id)) selectedFolders.add(event.id);
    } else {
      if (!selectedFiles.remove(event.id)) selectedFiles.add(event.id);
    }

    emit(state.copyWith(
      selectedFolderIds: selectedFolders,
      selectedFileIds: selectedFiles,
    ));
  }

  void _onClearSelection(ClearSelection event, Emitter<BrowserState> emit) =>
      emit(state.copyWith(selectedFolderIds: {}, selectedFileIds: {}));

  void _onToggleSelectAll(ToggleSelectAll event, Emitter<BrowserState> emit) {
    final res = BrowserBatchHelper.toggleSelectAll(
      state: state,
      selectAll: event.selectAll,
    );
    emit(state.copyWith(
      selectedFolderIds: res.folderIds,
      selectedFileIds: res.fileIds,
    ));
  }

  Future<void> _onBatchDownload(
      BatchDownload event, Emitter<BrowserState> emit) async {
    try {
      final count = await BrowserBatchHelper.executeBatchDownload(
        state: state,
        repository: _repository,
        conflictResolver: event.conflictResolver,
      );
      if (count > 0) {
        emit(state.copyWith(selectedFolderIds: {}, selectedFileIds: {}));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'.replaceAll('Exception: ', '')));
    }
  }

  Future<void> _onDownloadFolder(
      DownloadFolder event, Emitter<BrowserState> emit) async {
    try {
      await BrowserBatchHelper.executeDownloadFolder(
        folder: event.folder,
        repository: _repository,
        conflictResolver: event.conflictResolver,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'.replaceAll('Exception: ', '')));
    }
  }

  Future<void> _onExportFolderAsZip(
      ExportFolderAsZip event, Emitter<BrowserState> emit) async {
    try {
      await BrowserBatchHelper.executeExportFolderAsZip(
          folder: event.folder, repository: _repository);
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'.replaceAll('Exception: ', '')));
    }
  }

  Future<void> _onEnqueueDownload(
      EnqueueDownload event, Emitter<BrowserState> emit) async {
    try {
      await _repository.enqueueDownload(event.file,
          subpath: event.subpath, policy: event.policy);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Download failed to start: $e'));
    }
  }

  Future<void> _onEnqueueShare(
      EnqueueShare event, Emitter<BrowserState> emit) async {
    try {
      await _repository.enqueueWebShare(event.file,
          password: event.password,
          expiryDays: event.expiryDays,
          vanitySlug: event.vanitySlug);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Sharing failed to start: $e'));
    }
  }

  void _onNavigateUp(NavigateUp event, Emitter<BrowserState> emit) {
    if (state.category != null) {
      add(LoadDirectory(folderId: state.currentFolderId));
    } else if (state.currentFolderId != null) {
      add(LoadDirectory(
          folderId: _repository.getFolder(state.currentFolderId!)?.parentId));
    }
  }

  void _handleMutationResult(String? err, Emitter<BrowserState> emit) {
    if (err != null) {
      emit(state.copyWith(isLoading: false, errorMessage: err));
    } else {
      _reloadContents(emit, isOffline: state.isOffline);
    }
  }

  Future<void> _onCreateFolder(
      CreateFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final err = await BrowserMutationHelper.createFolder(
      name: event.name,
      parentId: state.currentFolderId,
      repository: _repository,
    );
    _handleMutationResult(err, emit);
  }

  Future<void> _onRenameFolder(
      RenameFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final err = await BrowserMutationHelper.renameFolder(
      folderId: event.folderId,
      newName: event.newName,
      repository: _repository,
    );
    _handleMutationResult(err, emit);
  }

  Future<void> _onDeleteFolder(
      DeleteFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final err = await BrowserMutationHelper.deleteFolder(
      folderId: event.folderId,
      repository: _repository,
    );
    _handleMutationResult(err, emit);
  }

  Future<void> _onRenameFile(
      RenameFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final err = await BrowserMutationHelper.renameFile(
      fileId: event.fileId,
      newName: event.newName,
      repository: _repository,
    );
    _handleMutationResult(err, emit);
  }

  Future<void> _onMoveFile(MoveFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await BrowserMutationHelper.moveFile(
        fileId: event.fileId,
        targetFolderId: event.targetFolderId,
        repository: _repository,
      );
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onCopyFile(CopyFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final err = await BrowserMutationHelper.copyFile(
      fileId: event.fileId,
      targetFolderId: event.targetFolderId,
      repository: _repository,
    );
    _handleMutationResult(err, emit);
  }

  Future<void> _onDeleteFile(
      DeleteFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final err = await BrowserMutationHelper.deleteFile(
      fileId: event.fileId,
      repository: _repository,
    );
    _handleMutationResult(err, emit);
  }

  Future<void> _onBatchDelete(
      BatchDelete event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await BrowserBatchHelper.executeBatchDelete(
        folderIds: state.selectedFolderIds,
        fileIds: state.selectedFileIds,
        repository: _repository,
      );
      emit(state.copyWith(selectedFolderIds: {}, selectedFileIds: {}));
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onBatchMove(BatchMove event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await BrowserBatchHelper.executeBatchMove(
        folderIds: state.selectedFolderIds,
        fileIds: state.selectedFileIds,
        targetFolderId: event.targetFolderId,
        repository: _repository,
      );
      emit(state.copyWith(selectedFolderIds: {}, selectedFileIds: {}));
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> _onBatchCopy(BatchCopy event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    try {
      await BrowserBatchHelper.executeBatchCopy(
        folderIds: state.selectedFolderIds,
        fileIds: state.selectedFileIds,
        targetFolderId: event.targetFolderId,
        repository: _repository,
      );
      emit(state.copyWith(selectedFolderIds: {}, selectedFileIds: {}));
      _reloadContents(emit, isOffline: state.isOffline);
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  void _onSetClipboard(SetClipboard event, Emitter<BrowserState> emit) =>
      emit(state.copyWith(
        clipboardMode: event.mode,
        clipboardFileIds: event.fileIds,
        clipboardFolderIds: event.folderIds,
        clipboardSourceFolderId: event.sourceFolderId,
        selectedFolderIds: {},
        selectedFileIds: {},
      ));

  void _onClearClipboard(ClearClipboard event, Emitter<BrowserState> emit) =>
      emit(state.copyWith(clearClipboard: true));

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
      if (mode != null) {
        await BrowserBatchHelper.executePasteClipboard(
          mode: mode,
          folderIds: state.clipboardFolderIds,
          fileIds: state.clipboardFileIds,
          targetFolderId: targetFolderId,
          repository: _repository,
        );
      }
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
