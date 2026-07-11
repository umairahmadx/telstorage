# Inline Download Progress Design Spec

Implement a non-blocking, reactive inline download progress UI for files in the browser screen.

## Goals
* Route all user-initiated downloads (small files, large files, web downloads) through the background `DownloadQueueService`.
* Rebuild and render tiles in the browser screen reactively using the download queue's `listenable` state.
* Display the download percentage directly on the item's thumbnail / placeholder.
* Display a linear progress bar and size details (e.g., `1.2 MB / 9.0 MB`) below the file name during active downloads.

---

## User Review Required
No blocking or breaking changes. The blocking modal progress dialog will be removed in favor of a smooth inline downloading experience.

---

## Proposed Changes

### Browser Screen Component

#### [MODIFY] [browser_screen.dart](file:///c:/Users/umair-dell/StudioProjects/telstorage/lib/features/browser/screens/browser_screen.dart)
* Change `_downloadAndView` to:
  * Enqueue the download using `ServiceLocator.instance.downloadQueue.enqueueDownload(file)`.
  * Show a quick non-blocking snackbar notifying that the download has started.
  * Remove the blocking modal `_showProgressDialog`.
* Wrap the file grid/list items (or `_FileTile` and `_GridFileItem` individually) in a `ValueListenableBuilder<Box<DownloadJob>>` connected to `ServiceLocator.instance.downloadQueue.listenable`.
* For `_FileTile` (List View):
  * Retrieve the active `DownloadJob` for `file.fileId`.
  * If the status is `'queued'` or `'downloading'`:
    * Overlay the `ThumbnailWidget` with a semi-transparent dark stack, a centered `CircularProgressIndicator`, and the progress percentage (e.g. `45%`).
    * Replace the subtitle text (file size & date) with a Column containing a `LinearProgressIndicator` and a status text like: `Downloading... 1.2 MB / 9.0 MB (45%)`.
* For `_GridFileItem` (Grid View):
  * Retrieve the active `DownloadJob` for `file.fileId`.
  * If the status is `'queued'` or `'downloading'`:
    * Overlay the `ThumbnailWidget` with a semi-transparent dark stack, a centered `CircularProgressIndicator`, and the progress percentage.
    * Append a `LinearProgressIndicator` below the file name.

---

## Verification Plan

### Manual Verification
1. Click on a small file (< 19 MB) on both Web and Native emulator.
2. Verify that:
   * No blocking progress dialog is shown.
   * The thumbnail immediately displays a dark overlay with circular progress and percentage.
   * The subtitle/grid space shows a linear progress bar and size indicator (`X.X MB / Y.Y MB`).
   * Once completed, the file tile reverts to its normal state.
3. Test with multiple simultaneous downloads to verify they queue and download correctly (up to 3 concurrent downloads, as per queue service settings).
