# Fix Folder Traversal & Multiselect File Resolution in Subfolders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix the data source in folder traversal and multiselect operations so that nested folders and files inside subfolders are correctly resolved for Download Folder, Export as ZIP, and Multiselect Batch Download.

**Architecture:** Replace the 6 call sites passing `getFolders(null)` and `getFiles(null)` with `currentFolders` and `currentFiles` from `StorageReader`. Update test mocks and add test coverage for nested folder batch operations.

**Tech Stack:** Flutter / Dart, Bloc, Hive, Flutter Test

---

### Task 1: Update Browser Dialogs and Browser Screen Data Sources

**Files:**
- Modify: `lib/features/browser/presentation/screens/browser/widgets/browser_dialogs.dart:270-330`
- Modify: `lib/features/browser/presentation/screens/browser/browser_screen.dart:400-420`

- [ ] **Step 1: Update `downloadFolder` and `exportFolderAsZip` in `browser_dialogs.dart`**
Replace `repo.getFolders(null)` and `repo.getFiles(null)` with `repo.currentFolders` and `repo.currentFiles`.

- [ ] **Step 2: Update `_handleBatchDownload` in `browser_screen.dart`**
Replace `repo.getFolders(null)` and `repo.getFiles(null)` with `repo.currentFolders` and `repo.currentFiles`.

---

### Task 2: Update Browser Batch Helper

**Files:**
- Modify: `lib/features/browser/presentation/screens/browser/viewmodel/browser_batch_helper.dart:50-125`

- [ ] **Step 1: Update `executeBatchDownload`, `executeDownloadFolder`, and `executeExportFolderAsZip`**
Replace all occurrences of `repository.getFolders(null)` and `repository.getFiles(null)` with `repository.currentFolders` and `repository.currentFiles`.

---

### Task 3: Update Test Mock and Add Unit Tests

**Files:**
- Modify: `test/features/browser/viewmodel/browser_bloc_batch_test.dart`

- [ ] **Step 1: Implement `currentFolders` and `currentFiles` in `_FakeStorageRepository`**
- [ ] **Step 2: Add test cases for multiselect in subfolder, download folder with nested files, and export as ZIP**
- [ ] **Step 3: Run `flutter test` to verify all tests pass**
