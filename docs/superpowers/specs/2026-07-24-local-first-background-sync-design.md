# Local-First Optimistic Architecture & Telegram Background Sync Engine

## Goal Description
Enhance TelStorage storage architecture to provide instant (sub-millisecond) local-first execution for all file/folder mutations (Create Folder, Rename, Move/Cut, Copy, Delete), coupled with a resilient persistent background sync engine that syncs changes to Telegram metadata messages whenever internet connectivity is restored.

---

## 1. Local-First Optimistic Mutation Strategy

All repository mutations (`StorageRepository`) perform local Isar/Hive database updates synchronously first, then enqueue persistent tasks into `SyncQueueService`.

### Mutation Flows
1. **Create Folder**:
   - Save `FolderRecord` to local DB immediately.
   - Enqueue `createFolder` action (`id`, `name`, `parentId`).
   - Trigger `SyncQueueService.processQueue()`.
2. **Rename Folder**:
   - Update `FolderRecord` in local DB immediately.
   - Enqueue `renameFolder` action (`folderId`, `name`).
   - Trigger `SyncQueueService.processQueue()`.
3. **Delete Folder**:
   - Remove `FolderRecord` from local DB immediately.
   - Enqueue `deleteFolder` action (`folderId`).
   - Trigger `SyncQueueService.processQueue()`.
4. **Rename File**:
   - Update `FileRecord` in local DB immediately.
   - Enqueue `renameFile` action (`fileId`, `name`).
   - Trigger `SyncQueueService.processQueue()`.
5. **Move File**:
   - Update `FileRecord.folderId` in local DB immediately.
   - Enqueue `moveFile` action (`fileId`, `folderId`).
   - Trigger `SyncQueueService.processQueue()`.
6. **Copy File**:
   - Save duplicate `FileRecord` (with `_copy` suffix) to local DB immediately.
   - Enqueue `copyFile` action (`originalFileId`, `newFileId`, `targetFolderId`, `newName`).
   - Trigger `SyncQueueService.processQueue()`.
7. **Delete File**:
   - Delete `FileRecord` from local DB immediately.
   - Enqueue `deleteFile` action (`fileId`, `metadataMessageId`, `metadataFileId`, `sizeMb`, `mimeType`).
   - Trigger `SyncQueueService.processQueue()`.

---

## 2. Background Sync Engine (`SyncQueueService`)

- **Persistence**: Managed via Hive box `pendingActionsBox`.
- **Automatic Reconnection Listener**: Listens to connectivity changes. When `Connectivity.hasConnection()` transitions to `true`, automatically invokes `processQueue()`.
- **Action Processing**:
  - Sort actions by `timestamp` (FIFO).
  - Execute corresponding `FileManagerService` remote operation.
  - On remote success: remove task from `pendingActionsBox`.
  - On network error / timeout: retain task in `pendingActionsBox` for retry when connection returns.
  - On non-recoverable error (e.g. Remote resource missing): log warning and clear task to prevent infinite blocking.

---

## 3. Real-Time UI Sync Status

- `BrowserBloc` listens to `_pendingBox` changes or polls `SyncQueueService.pendingCount`.
- Emits `pendingActionsCount` in `BrowserState`.
- `BrowserScreen` displays a sleek sync status pill in the AppBar when `pendingActionsCount > 0` (e.g., `☁️ 2 pending sync`).

---

## Verification Plan

### Manual Verification
1. Turn off Wi-Fi/Mobile Data (airplane mode).
2. Perform operations in Files tab: Create folder, rename file, cut file to folder, copy file to folder, delete file.
3. Observe UI updates **instantly** in less than 1 second while offline.
4. Verify App Bar displays pending sync badge (`☁️ 5 pending`).
5. Re-enable network connectivity.
6. Verify background queue processes all 5 tasks and updates Telegram cloud metadata without any UI interruption or errors.
