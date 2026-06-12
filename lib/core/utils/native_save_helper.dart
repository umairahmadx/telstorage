// Native save helper — Android, iOS, Desktop.
// Imported conditionally — not compiled on web.

import 'dart:io';
import 'dart:typed_data';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'app_logger.dart';
import 'file_category_helper.dart';

/// Result from a native save operation.
class NativeSaveResult {
  final String? savedPath;
  final String message;
  final bool success;
  const NativeSaveResult({this.savedPath, required this.message, required this.success});
}

/// Save [bytes] as [filename] to the platform's public Downloads/Files location.
Future<NativeSaveResult> saveNative(Uint8List bytes, String filename) async {
  if (Platform.isAndroid) {
    return _saveAndroid(bytes, filename);
  } else if (Platform.isIOS) {
    return _saveIos(bytes, filename);
  } else {
    return _saveDesktop(bytes, filename);
  }
}

// ── Android ──────────────────────────────────────────────────────────────────

Future<NativeSaveResult> _saveAndroid(Uint8List bytes, String filename) async {
  // Android < 10: need WRITE_EXTERNAL_STORAGE permission
  // Android 10+: scoped storage — write to public Downloads via direct path
  try {
    final sdkInt = await _androidSdk();
    if (sdkInt < 29) {
      final status = await Permission.storage.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        return const NativeSaveResult(
          success: false,
          message: '❌ Storage permission denied. Please allow in app Settings.',
        );
      }
    }

    final dlPath = await _androidDownloadsPath();
    final subfolder = getSubfolderForExtension(filename);
    final targetDir = Directory(p.join(dlPath, 'TelStorage', subfolder));
    await targetDir.create(recursive: true);

    final file = File(p.join(targetDir.path, filename));
    await file.writeAsBytes(bytes);
    AppLogger.i('Android: saved to ${file.path}', tag: 'SaveHelper');

    // Try to open the file — allows user to see it immediately
    try {
      await OpenFile.open(file.path);
    } catch (_) {}

    return NativeSaveResult(
      success: true,
      savedPath: file.path,
      message: '✅ Saved to Downloads: TelStorage/$subfolder/$filename',
    );
  } catch (e) {
    // Fallback to app Documents
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final subfolder = getSubfolderForExtension(filename);
      final targetDir = Directory(p.join(dir.path, 'TelStorage', subfolder));
      await targetDir.create(recursive: true);

      final file = File(p.join(targetDir.path, filename));
      await file.writeAsBytes(bytes);
      return NativeSaveResult(
        success: true,
        savedPath: file.path,
        message: '✅ Saved to app storage: TelStorage/$subfolder/$filename',
      );
    } catch (e2) {
      return NativeSaveResult(success: false, message: '❌ Save failed: $e2');
    }
  }
}

// ── iOS ───────────────────────────────────────────────────────────────────────

Future<NativeSaveResult> _saveIos(Uint8List bytes, String filename) async {
  try {
    // Save to Documents — visible in iOS Files app (UIFileSharingEnabled=true)
    final dir  = await getApplicationDocumentsDirectory();
    final subfolder = getSubfolderForExtension(filename);
    final targetDir = Directory(p.join(dir.path, 'TelStorage', subfolder));
    await targetDir.create(recursive: true);

    final file = File(p.join(targetDir.path, filename));
    await file.writeAsBytes(bytes);
    AppLogger.i('iOS: saved to ${file.path}', tag: 'SaveHelper');

    // Show share sheet so user can "Save to Files", "Save to Photos", AirDrop…
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, name: filename)],
        text: 'Downloaded from TelStorage',
      ),
    );

    return NativeSaveResult(
      success: true,
      savedPath: file.path,
      message: '✅ File ready — use the share sheet to save to Files or Photos.',
    );
  } catch (e) {
    return NativeSaveResult(success: false, message: '❌ Save failed: $e');
  }
}

// ── Desktop ───────────────────────────────────────────────────────────────────

Future<NativeSaveResult> _saveDesktop(Uint8List bytes, String filename) async {
  try {
    final dir  = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final subfolder = getSubfolderForExtension(filename);
    final targetDir = Directory(p.join(dir.path, 'TelStorage', subfolder));
    await targetDir.create(recursive: true);

    final file = File(p.join(targetDir.path, filename));
    await file.writeAsBytes(bytes);
    try { await OpenFile.open(file.path); } catch (_) {}
    return NativeSaveResult(
      success: true,
      savedPath: file.path,
      message: '✅ Saved to TelStorage/$subfolder',
    );
  } catch (e) {
    return NativeSaveResult(success: false, message: '❌ Save failed: $e');
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<String> _androidDownloadsPath() async {
  try {
    final ext = await getExternalStorageDirectory();
    if (ext != null) {
      // Typical path: /storage/emulated/0/Android/data/<pkg>/files
      // Downloads is:  /storage/emulated/0/Download
      final root = ext.path.split('Android').first;
      final dlPath = '${root}Download';
      await Directory(dlPath).create(recursive: true);
      return dlPath;
    }
  } catch (_) {}
  return '/storage/emulated/0/Download';
}

Future<int> _androidSdk() async {
  // Return a conservative 29+ for modern devices
  // In production you'd use device_info_plus to get the real SDK int
  return 29;
}
