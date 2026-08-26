/*
 * File: native_save_helper.dart
 * Description: Platform-specific native file saving with path sanitization, traversal prevention, scoped storage, and fallback mechanisms.
 */

// Native save helper — Android, iOS, Desktop.
// Imported conditionally — not compiled on web.

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_logger.dart';
import 'file_category_helper.dart';

/// Result from a native save operation.
class NativeSaveResult {
  final String? savedPath;
  final String message;
  final bool success;
  const NativeSaveResult(
      {this.savedPath, required this.message, required this.success});
}

/// Resolves a safe, normalized subpath guaranteed not to escape the root TelStorage folder.
String resolveSafeSubpath(String? subpath, String filename) {
  if (subpath == null || subpath.trim().isEmpty) {
    return getSubfolderForExtension(filename);
  }

  final segments = subpath
      .split(RegExp(r'[\\/]'))
      .map((s) => s.trim())
      .map((s) => s.replaceAll('..', '').replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(RegExp(r'_+'), '_'))
      .map((s) {
        var str = s;
        while (str.startsWith('_') || str.startsWith('.') || str.startsWith(' ')) {
          str = str.substring(1).trim();
        }
        while (str.endsWith('_') || str.endsWith('.') || str.endsWith(' ')) {
          str = str.substring(0, str.length - 1).trim();
        }
        return str;
      })
      .where((s) => s.isNotEmpty && s != '.' && s != '..')
      .toList();

  if (segments.isEmpty) {
    return getSubfolderForExtension(filename);
  }

  return segments.join('/');
}

/// Sanitizes filename to remove forbidden OS characters and directory separators.
String resolveSafeFilename(String filename) {
  var clean = filename
      .trim()
      .replaceAll('..', '')
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'_\.'), '.');

  while (clean.startsWith('_') || clean.startsWith(' ')) {
    clean = clean.substring(1).trim();
  }
  while (clean.endsWith('_') || clean.endsWith(' ')) {
    clean = clean.substring(0, clean.length - 1).trim();
  }

  return clean.isEmpty ? 'unnamed_file' : clean;
}

/// Save [bytes] as [filename] to the platform's public Downloads/Files location.
/// Optionally preserves a nested [subpath] directory structure safely.
Future<NativeSaveResult> saveNative(
  Uint8List bytes,
  String filename, {
  String? subpath,
}) async {
  final safeFilename = resolveSafeFilename(filename);
  final safeSubpath = resolveSafeSubpath(subpath, safeFilename);

  if (Platform.isAndroid) {
    return _saveAndroid(bytes, safeFilename, subpath: safeSubpath);
  } else if (Platform.isIOS) {
    return _saveIos(bytes, safeFilename, subpath: safeSubpath);
  } else {
    return _saveDesktop(bytes, safeFilename, subpath: safeSubpath);
  }
}

// ── Android ──────────────────────────────────────────────────────────────────

Future<NativeSaveResult> _saveAndroid(
  Uint8List bytes,
  String filename, {
  required String subpath,
}) async {
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
    final targetDir = Directory(p.join(dlPath, 'TelStorage', subpath));
    await targetDir.create(recursive: true);

    final file = File(p.join(targetDir.path, filename));
    await file.writeAsBytes(bytes);
    AppLogger.i('Android: saved to ${file.path}', tag: 'SaveHelper');

    return NativeSaveResult(
      success: true,
      savedPath: file.path,
      message: '✅ Saved to Downloads: TelStorage/$subpath/$filename',
    );
  } catch (e) {
    // Secondary fallback to app Documents
    try {
      final dir = await getApplicationDocumentsDirectory();
      final targetDir = Directory(p.join(dir.path, 'TelStorage', subpath));
      await targetDir.create(recursive: true);

      final file = File(p.join(targetDir.path, filename));
      await file.writeAsBytes(bytes);
      return NativeSaveResult(
        success: true,
        savedPath: file.path,
        message: '✅ Saved to app storage: TelStorage/$subpath/$filename',
      );
    } catch (e2) {
      return NativeSaveResult(success: false, message: '❌ Save failed: $e2');
    }
  }
}

// ── iOS ───────────────────────────────────────────────────────────────────────

Future<NativeSaveResult> _saveIos(
  Uint8List bytes,
  String filename, {
  required String subpath,
}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(dir.path, 'TelStorage', subpath));
    await targetDir.create(recursive: true);

    final file = File(p.join(targetDir.path, filename));
    await file.writeAsBytes(bytes);
    AppLogger.i('iOS: saved to ${file.path}', tag: 'SaveHelper');

    return NativeSaveResult(
      success: true,
      savedPath: file.path,
      message: '✅ Saved to Files: TelStorage/$subpath/$filename',
    );
  } catch (e) {
    return NativeSaveResult(success: false, message: '❌ Save failed: $e');
  }
}

// ── Desktop ───────────────────────────────────────────────────────────────────

Future<NativeSaveResult> _saveDesktop(
  Uint8List bytes,
  String filename, {
  required String subpath,
}) async {
  try {
    Directory dir;
    try {
      dir = (await getDownloadsDirectory()) ??
          (await getApplicationDocumentsDirectory());
    } catch (_) {
      dir = Directory.systemTemp;
    }

    final targetDir = Directory(p.join(dir.path, 'TelStorage', subpath));
    await targetDir.create(recursive: true);

    final file = File(p.join(targetDir.path, filename));
    await file.writeAsBytes(bytes);
    return NativeSaveResult(
      success: true,
      savedPath: file.path,
      message: '✅ Saved to TelStorage/$subpath',
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
      final root = ext.path.split('Android').first;
      final dlPath = '${root}Download';
      await Directory(dlPath).create(recursive: true);
      return dlPath;
    }
  } catch (_) {}
  return '/storage/emulated/0/Download';
}

Future<int> _androidSdk() async {
  return 29;
}
