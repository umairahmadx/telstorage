/*
 * File: download_disk_writer.dart
 * Description: Conditional export for platform-specific DownloadDiskWriter implementation.
 */

export 'download_disk_writer_native.dart'
    if (dart.library.js_interop) 'download_disk_writer_web.dart';
