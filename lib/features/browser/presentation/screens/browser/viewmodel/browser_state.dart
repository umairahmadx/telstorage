/// File: browser_state.dart
/// Description: State representation of the file browser, including selections, sorting, and directory data.
library;

import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/models/folder_record.dart';
import 'browser_event.dart';

/// Comprehensive state of the file browser.
class BrowserState {
  /// Loading state indicator flag.
  final bool isLoading;

  /// Flag indicating if initial directory fetch completed.
  final bool isInitialized;

  /// Current directory identifier (null for root).
  final String? currentFolderId;

  /// Current category filter name (null for all).
  final String? category;

  /// Subfolders in active directory.
  final List<FolderRecord> folders;

  /// Files in active directory.
  final List<FileRecord> files;

  /// Item count mapping for displayed folders.
  final Map<String, int> folderItemCounts;

  /// Current search string.
  final String searchQuery;

  /// Active sort criteria.
  final BrowserSortOption sortOption;

  /// Sorting order direction (true = ascending, false = descending).
  final bool sortAscending;

  /// Grouping hierarchy mode.
  final BrowserGroupOption groupOption;

  /// Layout mode (true = grid, false = list).
  final bool isGridView;

  /// Set of selected folder IDs in multi-select mode.
  final Set<String> selectedFolderIds;

  /// Set of selected file IDs in multi-select mode.
  final Set<String> selectedFileIds;

  /// Active clipboard mode (copy or move).
  final ClipboardMode? clipboardMode;

  /// Clipboard buffered file IDs.
  final Set<String> clipboardFileIds;

  /// Clipboard buffered folder IDs.
  final Set<String> clipboardFolderIds;

  /// Source directory of clipboard items.
  final String? clipboardSourceFolderId;

  /// Error message string, if an error occurred.
  final String? errorMessage;

  /// Offline connectivity status flag.
  final bool isOffline;

  /// Number of pending offline synchronization operations.
  final int pendingActionsCount;

  /// Constructs a BrowserState instance.
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

  /// True if multi-selection mode is active.
  bool get isMultiSelect =>
      selectedFolderIds.isNotEmpty || selectedFileIds.isNotEmpty;

  /// True if items exist in clipboard.
  bool get hasClipboard =>
      clipboardFileIds.isNotEmpty || clipboardFolderIds.isNotEmpty;

  /// Returns a copy of BrowserState with updated fields.
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
      currentFolderId:
          clearFolderId ? null : (currentFolderId ?? this.currentFolderId),
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
      clipboardMode:
          clearClipboard ? null : (clipboardMode ?? this.clipboardMode),
      clipboardFileIds: clearClipboard
          ? const {}
          : (clipboardFileIds ?? this.clipboardFileIds),
      clipboardFolderIds: clearClipboard
          ? const {}
          : (clipboardFolderIds ?? this.clipboardFolderIds),
      clipboardSourceFolderId: clearClipboard
          ? null
          : (clipboardSourceFolderId ?? this.clipboardSourceFolderId),
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isOffline: isOffline ?? this.isOffline,
      pendingActionsCount: pendingActionsCount ?? this.pendingActionsCount,
    );
  }
}
