# Error Handling, Resilience & KISS Rules

This document defines mandatory patterns for error management, network resilience, and code clarity in TelStorage.

---

## 1. KISS Principle (Keep It Simple & Direct)

- Prefer straightforward, readable code over deeply nested abstractions.
- Maintain single-responsibility classes and functions.
- Keep methods concise and focused.

---

## 2. Result Pattern (`Result<T>`) for Operations

- All asynchronous repository, use case, and network service methods MUST return a `Result<T>`:
  - `Success(T data)` for successful completion.
  - `Failure(String message, [dynamic exception])` for failures.
- Never let unhandled exceptions escape into UI layers or crash the application.

```dart
Future<Result<List<FileRecord>>> getFiles(String? folderId) async {
  try {
    final files = await _hiveService.getFilesInFolder(folderId);
    return Result.success(files);
  } catch (e, st) {
    AppLogger.error('Failed to load files', e, st);
    return Result.failure('Could not load files. Please try again.');
  }
}
```

---

## 3. Graceful UI Fallbacks

- Every screen and widget must handle loading, empty, and error states gracefully.
- Present user-friendly error banners/snackbars rather than raw stack traces.
- If offline, present offline indicators and allow local-first cached operations.

---

## 4. Background Queues & Retry Strategies

- Background transfer and sync queues (`SyncQueueService`, `TransferQueueService`, `WebShareQueueService`) must implement:
  - Exponential backoff / retry attempts for transient network failures.
  - Rate limiting compliance (e.g. Telegram API rate limiters).
  - Persistence across app restarts using Hive storage.

---

## 5. Defensive Read Paths for Persistent State

- Every persistent-state read (Hive boxes, SQLite, disk cache, JSON preferences) must assume a prior write could have been interrupted mid-record.
- Design read paths to degrade gracefully with fallbacks or auto-recovery rather than throwing unhandled schema or serialization errors.

---

## 6. Network Timeouts & Explicit Failure Behavior

- Every network operation must specify an explicit timeout (`.timeout(...)`).
- Define explicit behavior on failure: determine whether an operation should retry with exponential backoff, be enqueued into an offline queue, or immediately surface to the user.
- Every `await` touching network or disk must have a clear answer to *"what happens if this throws?"* rather than relying on default unhandled exception bubbling.

---

## 7. Offline-First by Design

- Design any new remote-writing or remote-modifying feature with offline resilience at the architectural level:
  - Cache mutations locally first (e.g. Hive state, `PendingAction` queues).
  - Sync to Telegram when connectivity is re-established.
  - Never bolt offline support onto a finished feature as an afterthought.


