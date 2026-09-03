/*
 * File: web_download_stub.dart
 * Description: Component and logic definition for web_download_stub.dart in TelStorage.
 */

import 'dart:typed_data';

// Native stub — this function is never called on native because
// DownloadService.saveAndOpen() checks kIsWeb first.
// It exists only so the conditional import compiles on non-web platforms.
void triggerWebDownload(Uint8List bytes, String filename) {
  throw UnsupportedError('Web download is not supported on this platform');
}
