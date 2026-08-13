import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/folder_record.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/connectivity.dart';
import '../../../core/events/domain_event_bus.dart';
import '../../storage/data/repositories/storage_repository.dart';
import '../screens/browser_screen.dart' show BrowserSortOption;

import 'browser_event.dart';
import 'browser_state.dart';

export 'browser_event.dart';
export 'browser_state.dart';

class BrowserBloc extends Bloc<BrowserEvent, BrowserState> {
  final StorageRepository _repository = ServiceLocator.instance.storageRepository;
  StreamSubscription? _foldersSubscription;
  StreamSubscription? _filesSubscription;
  StreamSubscription? _domainEventSubscription;

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
    _domainEventSubscription = DomainEventBus.instance.on<FileUploadedEvent>().listen((_) {
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
    final m = ascending ? 1 : -1;
    switch (option) {
      case BrowserSortOption.name:
        folders.sort((a, b) => m * a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        files.sort((a, b) => m * a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case BrowserSortOption.date:
        folders.sort((a, b) => m * a.createdAt.compareTo(b.createdAt));
        files.sort((a, b) => m * a.uploadedAt.compareTo(b.uploadedAt));
      case BrowserSortOption.size:
        files.sort((a, b) => m * a.sizeMb.compareTo(b.sizeMb));
    }
  }

  bool _matchesCategory(FileRecord file, String category) {
    final mime = file.mimeType.toLowerCase();
    final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
    final isImg = mime.startsWith('image/') || const ['jpg','jpeg','png','gif','webp','bmp','svg','heic'].contains(ext);
    final isVid = mime.startsWith('video/') || const ['mp4','mkv','mov','avi','webm','flv','wmv','m4v','3gp'].contains(ext);
    final isDoc = mime == 'application/pdf' || mime.contains('document') || mime.contains('word') || mime.startsWith('text/') || const ['pdf','doc','docx','txt','rtf','xls','xlsx','ppt','pptx','csv'].contains(ext);

    return switch (category) {
      'images' => isImg,
      'videos' => isVid,
      'docs' => isDoc,
      'others' => !isImg && !isVid && !isDoc,
      _ => true,
    };
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
    final res = await _repository.createFolder(event.name, parentId: state.currentFolderId);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
  }

  Future<void> _onRenameFolder(RenameFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final res = await _repository.renameFolder(event.folderId, event.newName);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
  }

  Future<void> _onDeleteFolder(DeleteFolder event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final res = await _repository.deleteFolder(event.folderId);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
  }

  Future<void> _onRenameFile(RenameFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final res = await _repository.renameFile(event.fileId, event.newName);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
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
    final res = await _repository.copyFile(event.fileId, event.targetFolderId);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
  }

  Future<void> _onDeleteFile(DeleteFile event, Emitter<BrowserState> emit) async {
    emit(state.copyWith(isLoading: true));
    final res = await _repository.deleteFile(event.fileId);
    res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        _reloadContents(emit, isOffline: state.isOffline);
      },
      (failure) => emit(state.copyWith(isLoading: false, errorMessage: failure.message)),
    );
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
    _domainEventSubscription?.cancel();
    return super.close();
  }
}
