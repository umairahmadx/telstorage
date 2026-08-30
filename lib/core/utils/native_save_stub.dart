/*
 * File: native_save_stub.dart
 * Description: Web stub for platform-specific native file saving and conflict resolution.
 */

import 'dart:typed_data';
import '../models/download_conflict_policy.dart';
import 'file_category_helper.dart';

export '../models/download_conflict_policy.dart';

class NativeSaveResult {
  final String? savedPath;
  final String message;
  final bool success;
  const NativeSaveResult(
      {this.savedPath, required this.message, required this.success});
}

String resolveSafeSubpath(String? subpath, String filename) =>
    subpath ?? getSubfolderForExtension(filename);

String resolveSafeFilename(String filename) =>
    filename.isEmpty ? 'unnamed_file' : filename;

Future<dynamic> resolveTargetDirectory({String? subpath}) async => null;

Future<String> resolveTargetFilePath(String filename, {String? subpath}) async =>
    filename;

Future<bool> doesTargetFileExist(String filename, {String? subpath}) async =>
    false;

Future<String> resolveNonCollidingFilename(String filename,
        {String? subpath, int maxAttempts = 100}) async =>
    filename;

Future<void> cleanStaleTempFiles({String? subpath}) async {}

Future<NativeSaveResult> saveNative(
  Uint8List bytes,
  String filename, {
  String? subpath,
  DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
}) =>
    throw UnsupportedError('Use web download on web platform');

