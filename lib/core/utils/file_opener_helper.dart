/*
 * File: file_opener_helper.dart
 * Description: Centralized utility for robust local file opening with accurate MIME type resolution, multi-stage OS app fallback, and user feedback.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'app_logger.dart';

/// Centralized helper for opening files in system applications.
abstract final class FileOpenerHelper {
  /// Known extensions not always registered in basic MIME tables.
  static const Map<String, String> _customMimeMap = {
    'heic': 'image/heic',
    'heif': 'image/heif',
    'webp': 'image/webp',
    'mkv': 'video/x-matroska',
    'flac': 'audio/flac',
    'apk': 'application/vnd.android.package-archive',
    'epub': 'application/epub+zip',
    'md': 'text/markdown',
    'log': 'text/plain',
    'json': 'application/json',
    'yaml': 'text/yaml',
    'yml': 'text/yaml',
    'dart': 'text/plain',
    'sql': 'application/sql',
    'csv': 'text/csv',
    'tsv': 'text/tab-separated-values',
    'rtf': 'application/rtf',
    '7z': 'application/x-7z-compressed',
    'tar': 'application/x-tar',
    'gz': 'application/gzip',
  };

  /// Resolves the most accurate MIME type for a file.
  ///
  /// Priority:
  /// 1. Explicit [mimeType] (if not empty and not generic `application/octet-stream`).
  /// 2. [lookupMimeType] based on path or filename.
  /// 3. [_customMimeMap] for known specific extensions.
  /// 4. Fallback to `*/*` if extension is unknown or missing (prompts OS all-apps chooser).
  static String resolveMimeType({
    String? mimeType,
    String? fileName,
    String? filePath,
  }) {
    if (mimeType != null &&
        mimeType.trim().isNotEmpty &&
        mimeType != 'application/octet-stream') {
      return mimeType.trim().toLowerCase();
    }

    final candidate = filePath ?? fileName ?? '';
    if (candidate.isNotEmpty) {
      final detected = lookupMimeType(candidate);
      if (detected != null && detected != 'application/octet-stream') {
        return detected.toLowerCase();
      }

      final ext = p.extension(candidate).toLowerCase().replaceFirst('.', '');
      if (_customMimeMap.containsKey(ext)) {
        return _customMimeMap[ext]!;
      }
    }

    // Universal wildcard fallback — prompts OS to show all capable apps
    return '*/*';
  }

  /// Opens a local file with the appropriate external system application.
  ///
  /// Automatically resolves MIME type, checks existence, applies a fallback
  /// retry with wildcard if no direct app was found, and provides visual user feedback.
  static Future<bool> openFile(
    BuildContext? context, {
    required String filePath,
    String? mimeType,
    String? fileName,
    ScaffoldMessengerState? messenger,
  }) async {
    final effectiveMessenger = messenger ??
        (context != null && context.mounted
            ? ScaffoldMessenger.maybeOf(context)
            : null);

    if (filePath.trim().isEmpty) {
      AppLogger.w('FileOpenerHelper: Empty file path provided');
      return false;
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      AppLogger.w('FileOpenerHelper: File does not exist at $filePath');
      _showFeedback(
        effectiveMessenger,
        'File not found on device. It may have been moved or deleted.',
      );
      return false;
    }

    final effectiveName = fileName ?? p.basename(filePath);
    final resolvedMime = resolveMimeType(
      mimeType: mimeType,
      fileName: effectiveName,
      filePath: filePath,
    );

    AppLogger.i(
      'FileOpenerHelper: Opening "$effectiveName" (MIME: $resolvedMime)',
      tag: 'FileOpener',
    );

    // Primary attempt: use specific MIME type if resolved, or null for wildcard
    final passType = resolvedMime == '*/*' ? null : resolvedMime;
    var result = await OpenFile.open(filePath, type: passType);

    // If specific MIME type had no matching app or error, fallback retry with wildcard to show all apps
    final isFailure = result.type != ResultType.done;
    final isNoAppOrError = isFailure &&
        (result.type == ResultType.noAppToOpen ||
            result.type == ResultType.error ||
            result.message.toLowerCase().contains('no app'));

    if (isNoAppOrError && passType != null) {
      AppLogger.w(
        'FileOpenerHelper: No app for $passType, falling back to all-apps chooser',
        tag: 'FileOpener',
      );
      result = await OpenFile.open(filePath);
    }

    return _handleOpenResult(effectiveMessenger, result, effectiveName);
  }

  /// Handles the [OpenResult] and provides haptics or user-facing feedback.
  static bool _handleOpenResult(
    ScaffoldMessengerState? messenger,
    OpenResult result,
    String fileName,
  ) {
    switch (result.type) {
      case ResultType.done:
        HapticFeedback.lightImpact();
        return true;

      case ResultType.fileNotFound:
        _showFeedback(
          messenger,
          'File not found. It may have been moved or deleted.',
        );
        return false;

      case ResultType.noAppToOpen:
        final ext = p.extension(fileName);
        _showFeedback(
          messenger,
          'No application found on your device to open this file${ext.isNotEmpty ? ' ($ext)' : ''}.',
        );
        return false;

      case ResultType.permissionDenied:
        _showFeedback(
          messenger,
          'Permission denied to access this file.',
        );
        return false;

      case ResultType.error:
        final ext = p.extension(fileName);
        final isNoApp = result.message.toLowerCase().contains('no app');
        final message = isNoApp
            ? 'No application found on your device to open this file${ext.isNotEmpty ? ' ($ext)' : ''}.'
            : (result.message.isNotEmpty
                ? result.message
                : 'Could not open file.');
        _showFeedback(messenger, message);
        return false;
    }
  }

  /// Helper to display a consistent floating feedback message if messenger is available.
  static void _showFeedback(
    ScaffoldMessengerState? messenger,
    String message,
  ) {
    if (messenger != null && messenger.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}
