# Share to TelStorage upload flow

## User flow

1. The user chooses **Share** or **Send to** in another app and selects TelStorage.
2. TelStorage accepts one or more files and opens an **Upload to TelStorage** destination sheet.
3. The sheet shows the shared filenames, lets the user browse the existing folder tree, and marks the current destination. The root folder is the default.
4. The user taps **Upload**. TelStorage creates upload tasks for the selected destination and opens the existing Transfers > Uploads view.
5. The existing upload queue reports progress, retries, cancellation, and completion. If the user cancels the destination sheet, no upload starts and temporary copies are removed.

## Lifecycle and permission requirements

- Handle both cold-start shares (app not running) and warm shares (app already open), including multiple files.
- Buffer shares until authentication and service initialization finish. Do not discard a cold-start share when the user must sign in first.
- Take a private, app-owned copy of each incoming content URI before the sender's temporary grant expires. Use that copy as the queued upload source and delete it only after completion or explicit cancellation.
- Do not request broad photo-library or all-files access for a share. The operating system grants access to the specific shared item. Request any additional permission only if the selected flow truly needs it.
- Validate that each item resolves to a readable file, use its shared filename (falling back to the copied path basename), and show per-item errors without dropping valid siblings. The existing uploader infers MIME type from the filename.
- Deduplicate delivery of the same OS intent so a cold-start item is not enqueued twice.
- If the destination is deleted or cannot be resolved before upload starts, stop and ask the user to select another folder.

## Implementation status and remaining platform work

Android `SEND`/`SEND_MULTIPLE` entry points, cold/warm intent intake, the destination sheet, and adaptation into the existing `UploadTask`/`UploadBloc` queue are implemented. The app also cleans app-owned shared copies after upload, cancel, or dismissal. `UploadFilePickerHelper` remains unchanged for in-app picking.

The iOS share sheet is not wired yet. It needs a Share Extension target, shared App Group storage, and Xcode project/signing configuration; adding only Dart code or an iOS URL scheme is insufficient. The current Windows environment cannot build or sign that target, so test the extension and app handoff in Xcode on macOS before treating iOS as supported.

## Acceptance checks

- One file and multiple files can be shared from another app while TelStorage is closed and while it is open.
- A cold-start share survives login and is presented once.
- The destination defaults to root and a nested folder can be selected before upload.
- Uploads use the existing queue and remain addressable in Transfers > Uploads.
- Cancel, unreadable source, unsupported share, and upload failure have visible outcomes and do not leak temporary files.
- Sharing a file does not trigger unrelated broad storage permission prompts.
