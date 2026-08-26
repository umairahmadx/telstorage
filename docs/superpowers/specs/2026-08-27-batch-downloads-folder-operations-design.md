# Batch Downloads & Folder Operations Specification

**Date**: 2026-08-27  
**Status**: Proposed  
**Target Feature**: Multi-Select Batch Downloads, Recursive Folder Download, ZIP Export, and Select All

---

## 1. Overview

This specification details the architecture and implementation of batch downloading and advanced folder operations in TelStorage. Users will be able to:
1. Select multiple files and folders in the Browser and enqueue all of them for download in one tap.
2. Select all / deselect all items in the current folder with a single click.
3. Download an entire folder recursively while preserving its nested folder hierarchy on disk (`Downloads/TelStorage/<Folder>/<Subfolder>/...`).
4. Export and compress an entire folder structure into a standalone `.zip` archive on the device.

---

## 2. User Experience & UI Workflow

### 2.1 Multi-Selection Bar (`AppBatchActionBar`)
- **Select All / Deselect All Button**:
  - Displays a dedicated toggle button: `Select All` (or `Deselect All` when all items are selected).
  - Tapping selects all files and folders currently visible in the active directory view.
- **Batch Download Action Button**:
  - The download icon (`Icons.download_rounded`) in `AppBatchActionBar` is wired to trigger `BatchDownload`.
  - Shows an aggregate confirmation dialog:
    - **Title**: *"Download Selected Items?"*
    - **Body**: *"Enqueue X files (Total: Y MB) for download?"*
    - **Buttons**: *"Cancel"* and *"Download"*.

### 2.2 Folder Actions Bottom Sheet (`BrowserDialogs.showFolderDetail`)
- Adds two new action items:
  1. **"Download Folder"** (`Icons.folder_zip_outlined` / `Icons.download_rounded`):
     - Recursively aggregates all child files.
     - Confirms total count and size.
     - Enqueues each file to `DownloadQueueService` with its relative directory path.
  2. **"Export as ZIP"** (`Icons.archive_outlined`):
     - Downloads all folder files to a transient staging cache.
     - Compresses them using Dart `archive` into `Downloads/TelStorage/zip/<folder_name>.zip`.
     - Displays live progress in the Transfers queue (`TransferTask`).
     - Offers an **"Open ZIP"** notification upon completion.

---

## 3. Architecture & Data Flow

### 3.1 Recursive File Traversal
`StorageRepository` (or `LruFolderCacheService`) is extended with:
```dart
Future<List<({FileRecord file, String relativePath})>> getDescendantFiles(String folderId);
```
- Performs a Breadth-First Search (BFS) / Depth-First Search (DFS) over folder children.
- Constructs relative paths (e.g. `SubFolder/Nested/image.png`).
- Returns all contained `FileRecord` entities with their relative folder path.

### 3.2 Subpath Preservation in Downloads
`DownloadJob` model is extended with an optional `subpath` property:
```dart
@HiveField(10)
final String? subpath; // e.g. "Work/Invoices"
```
When `DownloadQueueService` saves completed bytes via `saveNative`, it uses `subpath` to create the exact nested directories under `Downloads/TelStorage/` (or app documents on iOS/Desktop).

### 3.3 Folder ZIP Archive Service (`ZipArchiveService`)
A dedicated utility service in `lib/core/services/zip_archive_service.dart`:
1. Creates a `TransferTask` in `TransferQueueService` representing the ZIP export operation.
2. Downloads files in sequential/parallel chunks into a temporary scratch directory (`cache/zip_staging/<folderId>/`).
3. Uses `ZipFileEncoder` from `package:archive/archive_io.dart` to archive the directory into `<folder_name>.zip`.
4. Moves the final `.zip` file to the public Downloads folder using `native_save_helper`.
5. Cleans up temporary staging files.
6. Marks the task completed and posts a completion notification with an `open_<fileId>` action.

---

## 4. State Management (`BrowserBloc` Events & Handlers)

New and updated events in `BrowserBloc`:
- `ToggleSelectAll(bool selectAll)`: Selects or deselects all files and folders in `state.files` and `state.folders`.
- `BatchDownload()`: Enqueues all `selectedFileIds` and resolves `selectedFolderIds` recursively.
- `DownloadFolder(FolderRecord folder)`: Enqueues a specific folder recursively.
- `ExportFolderAsZip(FolderRecord folder)`: Initiates background ZIP export for the selected folder.

---

## 5. Resilience & Error Handling
- **Partial Failure Handling**: If an individual file in a batch download fails, the remaining files in the queue continue processing.
- **Cleanup Guarantee**: Staging folders for ZIP export are wrapped in `try-finally` blocks to ensure temporary chunk files are deleted even if an error occurs.
- **Disk Space Check**: Verifies available device space before starting huge multi-gigabyte ZIP exports.

---

## 6. Testing Strategy
1. **Unit Tests**:
   - Recursive folder traversal with nested subfolders and empty folders.
   - ZIP creation and structure validation.
   - `SelectAll` toggle logic in `BrowserBloc`.
2. **Architecture Compliance**:
   - Verify strict < 500 lines limit across all new and edited files.
   - Verify zero raw `Color(0x...)` in UI widgets.
   - Run `flutter analyze` and `flutter test`.
