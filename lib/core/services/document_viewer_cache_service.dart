/*
 * File: document_viewer_cache_service.dart
 * Description: High-performance document cache service managing disk caching, format detection, text decoding, and re-uploading edited files to Telegram.
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/app_cache_manager.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/utils/app_logger.dart';

/// Singleton service responsible for caching and editing documents.
class DocumentViewerCacheService {
  DocumentViewerCacheService._();

  /// Singleton instance of DocumentViewerCacheService.
  static final DocumentViewerCacheService instance =
      DocumentViewerCacheService._();

  /// In-flight download deduplication map.
  final Map<String, Future<File?>> _inFlightDownloads = {};

  /// Supported text and code extensions (without leading dot).
  static const Set<String> textExtensions = {
    'txt', 'md', 'json', 'csv', 'log', 'dart', 'py', 'js', 'ts', 'html',
    'css', 'xml', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'sh', 'bat', 'sql',
    'env', 'gitignore', 'properties', 'gradle', 'swift', 'kt', 'java', 'c',
    'cpp', 'h', 'rs', 'go', 'rb', 'php', 'lua',
  };

  /// Supported Office extensions (without leading dot).
  static const Set<String> officeExtensions = {
    'docx', 'xlsx', 'pptx', 'doc', 'xls', 'ppt', 'odt', 'ods', 'odp',
  };

  /// Checks if file is a PDF.
  static bool isPdfRecord(FileRecord file) {
    final ext = p.extension(file.name).toLowerCase().replaceFirst('.', '');
    return ext == 'pdf' || file.mimeType.toLowerCase() == 'application/pdf';
  }

  /// Checks if file is a text or code document.
  static bool isTextRecord(FileRecord file) {
    final ext = p.extension(file.name).toLowerCase().replaceFirst('.', '');
    if (textExtensions.contains(ext)) return true;
    final mime = file.mimeType.toLowerCase();
    return mime.startsWith('text/') ||
        mime == 'application/json' ||
        mime == 'application/xml';
  }

  /// Checks if file is an Office document.
  static bool isOfficeRecord(FileRecord file) {
    final ext = p.extension(file.name).toLowerCase().replaceFirst('.', '');
    return officeExtensions.contains(ext);
  }

  /// Checks if file is viewable or supported by the document viewer.
  static bool isDocumentRecord(FileRecord file) {
    return isPdfRecord(file) || isTextRecord(file) || isOfficeRecord(file);
  }

  /// Resolves the dedicated local cache file path for a document.
  Future<File> getCacheTargetFile(FileRecord file) async {
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory('${tempDir.path}/document_cache');
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }
    final ext = p.extension(file.name);
    return File('${cacheDir.path}/${file.fileId}$ext');
  }

  /// Checks if a document is already cached on disk.
  Future<File?> getCachedFile(FileRecord file) async {
    if (kIsWeb) return null;
    try {
      final cacheFile = await getCacheTargetFile(file);
      if (cacheFile.existsSync() && cacheFile.lengthSync() > 0) {
        try {
          cacheFile.setLastModifiedSync(DateTime.now());
        } catch (_) {}
        return cacheFile;
      }

      if (ServiceLocator.instance.isInitialized) {
        final completedPath =
            ServiceLocator.instance.downloadQueue.getCompletedPath(file.fileId);
        if (completedPath != null) {
          final completed = File(completedPath);
          if (completed.existsSync() && completed.lengthSync() > 0) {
            return completed;
          }
        }
      }
    } catch (e) {
      AppLogger.w('Error checking cached document file: $e',
          tag: 'DocumentViewerCacheService');
    }
    return null;
  }

  /// Downloads or retrieves cached document file.
  Future<File?> getOrDownloadFile(
    FileRecord file, {
    void Function(double progress, String status)? onProgress,
  }) async {
    if (kIsWeb) return null;

    final existing = await getCachedFile(file);
    if (existing != null) {
      onProgress?.call(1.0, 'Ready');
      return existing;
    }

    if (_inFlightDownloads.containsKey(file.fileId)) {
      return _inFlightDownloads[file.fileId]!;
    }

    final downloadFuture = () async {
      try {
        onProgress?.call(0.05, 'Starting…');
        final bytes = await ServiceLocator.instance.downloadService.downloadFile(
          file,
          (pct, status) => onProgress?.call(pct, status),
          priority: RequestPriority.immediate,
        );

        final targetFile = await getCacheTargetFile(file);
        final tempStaging = File('${targetFile.path}.tmp');
        await tempStaging.writeAsBytes(bytes, flush: true);

        if (targetFile.existsSync()) {
          try {
            targetFile.deleteSync();
          } catch (_) {}
        }
        await tempStaging.rename(targetFile.path);

        try {
          targetFile.setLastModifiedSync(DateTime.now());
        } catch (_) {}

        AppCacheManager.instance.enforceCacheLimit();
        AppLogger.i(
            'Cached document ${file.name} (${targetFile.lengthSync()} bytes)',
            tag: 'DocumentViewerCacheService');
        return targetFile;
      } catch (e) {
        AppLogger.w('Failed to download document: $e',
            tag: 'DocumentViewerCacheService');
        return null;
      } finally {
        _inFlightDownloads.remove(file.fileId);
      }
    }();

    _inFlightDownloads[file.fileId] = downloadFuture;
    return downloadFuture;
  }

  /// Reads UTF-8 text from cached file with fallback encoding handling.
  Future<String?> readTextContent(File file) async {
    try {
      final bytes = await file.readAsBytes();
      try {
        return utf8.decode(bytes);
      } catch (_) {
        return latin1.decode(bytes);
      }
    } catch (e) {
      AppLogger.e('Failed to read text content: $e',
          tag: 'DocumentViewerCacheService');
      return null;
    }
  }

  /// Saves edited text content back to Telegram by re-uploading and removing old record.
  Future<Result<FileRecord>> saveEditedFile(
    FileRecord oldRecord,
    String newContent, {
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      final encodedBytes = Uint8List.fromList(utf8.encode(newContent));
      final uploadResult = await ServiceLocator.instance.uploadService.uploadFile(
        encodedBytes,
        oldRecord.name,
        oldRecord.folderId,
        (progress, status) => onProgress?.call(progress, status),
      );

      if (uploadResult is Failure<Map<String, dynamic>>) {
        return Failure(uploadResult.failure);
      }

      final data = (uploadResult as Success<Map<String, dynamic>>).data;
      final newFileId = data['file_id'] as String? ?? '';
      final newRecord = ServiceLocator.instance.hive.getFile(newFileId);

      // Clean up previous remote and local file entry
      try {
        await ServiceLocator.instance.fileManager.deleteFile(oldRecord.fileId);
      } catch (e) {
        AppLogger.w('Could not delete superseded file: $e',
            tag: 'DocumentViewerCacheService');
      }

      // Update local cache target
      if (newRecord != null) {
        final newCacheFile = await getCacheTargetFile(newRecord);
        await newCacheFile.writeAsBytes(encodedBytes, flush: true);
        return Success(newRecord);
      }

      return Success(oldRecord);
    } catch (e) {
      AppLogger.e('Save edited file failed: $e',
          tag: 'DocumentViewerCacheService');
      return Failure(UnknownFailure(e.toString()));
    }
  }
}
