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
