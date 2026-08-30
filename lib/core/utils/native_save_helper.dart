/*
 * File: native_save_helper.dart
 * Description: Platform-specific native file saving with path sanitization, atomic overwrites, collision resolution, scoped storage, and fallback mechanisms.
 */

// Native save helper — Android, iOS, Desktop.
// Imported conditionally — not compiled on web.

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../models/download_conflict_policy.dart';
import 'app_logger.dart';
import 'file_category_helper.dart';

export '../models/download_conflict_policy.dart';

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
      .map((s) => s
          .replaceAll('..', '')
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll(RegExp(r'_+'), '_'))
      .map((s) {
        var str = s;
        while (
            str.startsWith('_') || str.startsWith('.') || str.startsWith(' ')) {
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

  while (clean.startsWith('_') || clean.startsWith(' ') || clean.startsWith('.')) {
    clean = clean.substring(1).trim();
  }
  while (clean.endsWith('_') || clean.endsWith(' ') || clean.endsWith('.')) {
    clean = clean.substring(0, clean.length - 1).trim();
  }

  return clean.isEmpty ? 'unnamed_file' : clean;
}

/// Resolves the destination directory on the device.
Future<Directory> resolveTargetDirectory({String? subpath}) async {
  final cleanSubpath =
      subpath != null && subpath.isNotEmpty ? subpath : 'other';
  if (Platform.isAndroid) {
    try {
      final dlPath = await _androidDownloadsPath();
      final dir = Directory(p.join(dlPath, 'TelStorage', cleanSubpath));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      final appDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(appDir.path, 'TelStorage', cleanSubpath));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
  } else if (Platform.isIOS) {
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(dir.path, 'TelStorage', cleanSubpath));
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }
    return targetDir;
  } else {
    Directory dir;
    try {
      dir = (await getDownloadsDirectory()) ??
          (await getApplicationDocumentsDirectory());
    } catch (_) {
      dir = Directory.systemTemp;
    }
    final targetDir = Directory(p.join(dir.path, 'TelStorage', cleanSubpath));
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }
    return targetDir;
  }
}

/// Resolves canonical target file path on disk.
Future<String> resolveTargetFilePath(String filename, {String? subpath}) async {
  final safeFilename = resolveSafeFilename(filename);
  final safeSubpath = resolveSafeSubpath(subpath, safeFilename);
  final targetDir = await resolveTargetDirectory(subpath: safeSubpath);
  return p.join(targetDir.path, safeFilename);
}

/// Checks if a file with the given name physically exists at destination.
Future<bool> doesTargetFileExist(String filename, {String? subpath}) async {
  try {
    final targetPath =
        await resolveTargetFilePath(filename, subpath: subpath);
    return File(targetPath).existsSync();
  } catch (_) {
    return false;
  }
}

/// Resolves a non-colliding filename (e.g. `file (1).png`, `file (2).png`).
/// Bounded to [maxAttempts] iterations, falling back to timestamp suffix.
Future<String> resolveNonCollidingFilename(
  String filename, {
  String? subpath,
  int maxAttempts = 100,
}) async {
  final safeFilename = resolveSafeFilename(filename);
  final safeSubpath = resolveSafeSubpath(subpath, safeFilename);

  if (!(await doesTargetFileExist(safeFilename, subpath: safeSubpath))) {
    return safeFilename;
  }

  final ext = p.extension(safeFilename);
  final nameWithoutExt = p.basenameWithoutExtension(safeFilename);

  for (var i = 1; i <= maxAttempts; i++) {
    final candidate = '$nameWithoutExt ($i)$ext';
    if (!(await doesTargetFileExist(candidate, subpath: safeSubpath))) {
      return candidate;
    }
  }

  return '${nameWithoutExt}_${DateTime.now().millisecondsSinceEpoch}$ext';
}

/// Sweeps and deletes orphaned temporary staging files in destination directory.
Future<void> cleanStaleTempFiles({String? subpath}) async {
  try {
    final dir = await resolveTargetDirectory(subpath: subpath);
    if (!dir.existsSync()) return;
    final entries = dir.listSync();
    for (final entry in entries) {
      if (entry is File) {
        final name = p.basename(entry.path);
        if (name.startsWith('.') && name.contains('.tmp_')) {
          try {
            await entry.delete();
          } catch (_) {}
        }
      }
    }
  } catch (_) {}
}

/// Writes [bytes] to [targetFile] via temporary staging file and atomic rename.
Future<void> _writeWithAtomicRename(File targetFile, Uint8List bytes) async {
  final parentDir = targetFile.parent;
  if (!parentDir.existsSync()) {
    await parentDir.create(recursive: true);
  }

  final baseName = p.basename(targetFile.path);
  final randSuffix = const Uuid().v4().substring(0, 8);
  final tempFile = File(
      '${parentDir.path}/.$baseName.tmp_${DateTime.now().microsecondsSinceEpoch}_$randSuffix');

  try {
    await tempFile.writeAsBytes(bytes, flush: true);
    final writtenLen = await tempFile.length();
    if (writtenLen != bytes.length) {
      throw Exception(
          'Staged file length mismatch: expected ${bytes.length} bytes, wrote $writtenLen');
    }

    if (targetFile.existsSync()) {
      try {
        await targetFile.delete();
      } catch (_) {}
    }

    await tempFile.rename(targetFile.path);
  } catch (e) {
    if (tempFile.existsSync()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
    rethrow;
  }
}

/// Save [bytes] as [filename] to the platform's public Downloads/Files location.
/// Optionally preserves a nested [subpath] directory structure safely.
Future<NativeSaveResult> saveNative(
  Uint8List bytes,
  String filename, {
  String? subpath,
  DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
}) async {
  var safeFilename = resolveSafeFilename(filename);
  final safeSubpath = resolveSafeSubpath(subpath, safeFilename);

  if (policy == DownloadConflictPolicy.keepBoth) {
    safeFilename = await resolveNonCollidingFilename(safeFilename,
        subpath: safeSubpath);
  } else if (policy == DownloadConflictPolicy.skip) {
    if (await doesTargetFileExist(safeFilename, subpath: safeSubpath)) {
      final existingPath =
          await resolveTargetFilePath(safeFilename, subpath: safeSubpath);
      return NativeSaveResult(
        success: true,
        savedPath: existingPath,
        message: 'File already exists (skipped download).',
      );
    }
  }

  if (Platform.isAndroid) {
    return _saveAndroid(bytes, safeFilename,
        subpath: safeSubpath, policy: policy);
  } else if (Platform.isIOS) {
    return _saveIos(bytes, safeFilename,
        subpath: safeSubpath, policy: policy);
  } else {
    return _saveDesktop(bytes, safeFilename,
        subpath: safeSubpath, policy: policy);
  }
}

// ── Android ──────────────────────────────────────────────────────────────────

Future<NativeSaveResult> _saveAndroid(
  Uint8List bytes,
  String filename, {
  required String subpath,
  required DownloadConflictPolicy policy,
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
    final file = File(p.join(targetDir.path, filename));
    await _writeWithAtomicRename(file, bytes);
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
      final file = File(p.join(targetDir.path, filename));
      await _writeWithAtomicRename(file, bytes);
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
  required DownloadConflictPolicy policy,
}) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(p.join(dir.path, 'TelStorage', subpath));
    final file = File(p.join(targetDir.path, filename));
    await _writeWithAtomicRename(file, bytes);
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
  required DownloadConflictPolicy policy,
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
    final file = File(p.join(targetDir.path, filename));
    await _writeWithAtomicRename(file, bytes);
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
