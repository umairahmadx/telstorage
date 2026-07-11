# Fast Metadata Sync with Background Fallback Design Spec

Optimize app startup synchronization by caching basic file metadata inside the global channel index, and asynchronously resolving older legacy file indices in the background.

## Goals
* Instant startup sync by avoiding individual Telegram download requests for files.
* Support full backwards compatibility with legacy file references that do not have expanded metadata.
* Unblock the user interface immediately by displaying skeleton placeholders for legacy files and updating them as details resolve in the background.

---

## User Review Required
No breaking changes. The app's startup synchronization will become significantly faster (near-instantaneous).

---

## Proposed Changes

### Data Layer Models

#### [MODIFY] [app_metadata.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/models/app_metadata.dart)
* Add optional/nullable metadata fields to the `FileRef` class:
  * `sizeMb`, `mimeType`, `uploadedAt` (as String), `chunkCount`, `sha256`, `metadataMessageId`, `thumbnailFileId`.
* Update the constructor, `FileRef.fromJson`, and `FileRef.toJson` to parse and serialize these new optional properties.

### Services Layer

#### [MODIFY] [metadata_service.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/services/metadata_service.dart)
* Update the `addFile` method to populate all the new optional properties on the `FileRef` instance when constructing it from `fileData`.

#### [MODIFY] [sync_service.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/core/services/sync_service.dart)
* Modify `syncFromTelegram`:
  * If a file reference (`FileRef`) does not exist in local Hive:
    * Check if `sizeMb` is non-null.
    * If present, instantiate the complete `FileRecord` from `FileRef` details and save it directly to Hive.
    * If missing (legacy file), instantiate a skeleton `FileRecord` (e.g. `sizeMb: 0.0`, `mimeType: 'application/octet-stream'`, `uploadedAt: DateTime.now()`, `chunkCount: 1`, `sha256Hash: ''`) and save it to Hive immediately.
    * Add the legacy `FileRef` to a background queue list.
  * Once the main loop finishes, trigger `_backgroundSyncOldFiles(legacyQueue)` in a fire-and-forget asynchronous call (without awaiting it), and return the `SyncResult` to unblock the UI.
* Implement `_backgroundSyncOldFiles(List<FileRef> legacyQueue)`:
  * Download the per-file JSON index from Telegram using `ref.metaFileId`.
  * Decode the JSON, parse the full `FileRecord`, and update it in Hive.
  * Rebuild / update dynamically.

---

## Verification Plan

### Manual Verification
1. Run the app on target platform (Web/Mobile).
2. Upload a new file, and verify that the global `.metadata.json` now includes the expanded metadata properties for the new file.
3. Simulate a fresh sync (e.g. clear local Hive data).
4. Verify that:
   * Startup sync finishes almost instantly.
   * Legacy files appear in the list with generic icons and sizes, then update to their correct attributes (thumbnails, sizes) dynamically in the background.
   * New files appear with correct thumbnails and sizes instantly.
