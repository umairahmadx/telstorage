import '../../../core/models/file_record.dart';
import '../../../core/models/folder_record.dart';
import '../screens/browser_screen.dart' show BrowserSortOption, BrowserGroupOption;
import 'browser_event.dart' show ClipboardMode;

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
