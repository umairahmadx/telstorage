# Batch Downloads & Folder Operations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement batch multi-select downloading, recursive folder downloads preserving hierarchy, one-click Select All/Deselect All, and folder export to ZIP.

**Architecture:** A dedicated `FolderTraversalService` performs BFS resolution of nested folders/files into relative paths. `DownloadJob` and `native_save_helper` accept optional `subpath` values to recreate folder hierarchies on device. `ZipArchiveService` leverages `package:archive` to package folder downloads into `.zip` files in the background with progress reporting via `TransferQueueService`.

**Tech Stack:** Flutter, Dart, `flutter_bloc`, `package:archive`, `open_file`, Hive.

## Global Constraints
- Strict file line limit: No file in `lib/` may exceed 500 lines.
- Zero hardcoded colors: All UI colors must use `AppColorsExtension` or `AppColors`.
- Full test coverage: Every task must have automated tests passing with `flutter test`.
- All `.dart` files in `lib/` must have a top-level multiline header `/* File: ... Description: ... */`.

---

### Task 1: Subpath Preservation in Download Models and Native Saver

**Files:**
- Modify: `lib/core/models/download_job.dart`
- Modify: `lib/core/utils/native_save_helper.dart`
- Modify: `lib/core/services/download_service_contract.dart`
- Modify: `lib/core/services/download_service.dart`
- Modify: `lib/core/services/download_queue_service.dart`
- Test: `test/core/utils/native_save_helper_test.dart`

**Interfaces:**
- Consumes: `DownloadJob`, `saveNative(bytes, filename)`
- Produces: `DownloadJob.subpath`, `saveNative(bytes, filename, {String? subpath})`, `saveAndOpen(bytes, filename, {String? subpath})`

- [x] **Step 1: Write the failing unit test for `native_save_helper` with subpath**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Update `native_save_helper.dart`, `DownloadJob`, and `DownloadService`**
- [x] **Step 4: Run test to verify it passes**

---

### Task 2: Folder Traversal & Recursive File Resolution Service

**Files:**
- Create: `lib/core/services/folder_traversal_service.dart`
- Test: `test/core/services/folder_traversal_service_test.dart`

**Interfaces:**
- Consumes: `HiveService.files`, `HiveService.folders`
- Produces: `FolderTraversalService.getDescendantFiles(String folderId)` returning `List<FolderFileItem>` with relative paths and aggregate size.

- [x] **Step 1: Write the failing unit test for `FolderTraversalService`**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement `FolderTraversalService`**
- [x] **Step 4: Run test to verify it passes**

---

### Task 3: Folder ZIP Archive Service (`ZipArchiveService`)

**Files:**
- Create: `lib/core/services/zip_archive_service.dart`
- Test: `test/core/services/zip_archive_service_test.dart`

**Interfaces:**
- Consumes: `package:archive/archive_io.dart`, `TelegramService`, `TransferQueueService`, `FolderTraversalService`
- Produces: `ZipArchiveService.exportFolderAsZip(FolderRecord folder)`

- [x] **Step 1: Write failing unit test for `ZipArchiveService`**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement `ZipArchiveService`**
- [x] **Step 4: Run test to verify it passes**

---

### Task 4: Multi-Select Select All & Batch Download in `BrowserBloc`

**Files:**
- Modify: `lib/features/browser/presentation/screens/browser/viewmodel/browser_event.dart`
- Modify: `lib/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart`
- Create: `lib/features/browser/presentation/screens/browser/viewmodel/browser_batch_helper.dart`
- Create: `lib/features/browser/presentation/screens/browser/viewmodel/browser_mutation_helper.dart`
- Test: `test/features/browser/viewmodel/browser_bloc_batch_test.dart`

**Interfaces:**
- Consumes: `ToggleSelectAll`, `BatchDownload`, `DownloadFolder`, `ExportFolderAsZip`
- Produces: Updated `BrowserState` with selected items, batch dispatch to `DownloadQueueService` / `ZipArchiveService`

- [x] **Step 1: Write failing unit test for `BrowserBloc` batch events**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement events and handlers in `browser_event.dart` and `browser_view_model.dart`**
- [x] **Step 4: Run test to verify it passes**

---

### Task 5: UI Integration in `AppBatchActionBar`, `BrowserScreen`, and `BrowserDialogs`

**Files:**
- Modify: `lib/shared/widgets/bars/app_batch_action_bar.dart`
- Modify: `lib/features/browser/presentation/screens/browser/browser_screen.dart`
- Modify: `lib/features/browser/presentation/screens/browser/widgets/browser_dialogs.dart`
- Test: `test/features/browser/browser_batch_ui_test.dart`

**Interfaces:**
- Consumes: `AppBatchActionBar`, `BrowserDialogs`
- Produces: Select All toggle button in UI, confirmation dialogs for batch download & folder download, "Download Folder" and "Export as ZIP" in folder options.

- [x] **Step 1: Write widget test for `AppBatchActionBar` Select All & Download buttons**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement UI updates in `AppBatchActionBar`, `browser_screen.dart`, and `browser_dialogs.dart`**
- [x] **Step 4: Run test to verify it passes**

---

### Task 6: Full Verification & Architecture Compliance

**Files:**
- Run: `flutter analyze`
- Run: `flutter test`

- [x] **Step 1: Run static analyzer**
Run: `flutter analyze` -> `No issues found! (0 errors, 0 warnings, 0 lints)`

- [x] **Step 2: Run all tests in the repository**
Run: `flutter test` -> `All tests passed! (131/131 tests passed, zero 500-line limit violations)`
