import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import '../utils/thumbnail_helper_native.dart'
    if (dart.library.js_interop) '../utils/thumbnail_helper_web.dart';
import 'telegram_service.dart';

class ThumbnailRepository {
  final TelegramService _telegram;
  final Map<String, Future<dynamic>> _activeDownloads = {};
  final Map<String, Uint8List> _webCache = {};

  ThumbnailRepository(this._telegram);

  Future<dynamic> getThumbnailData(FileRecord file) async {
    if (file.thumbnailFileId == null) return null;

    if (kIsWeb) {
      if (_webCache.containsKey(file.fileId)) {
        return _webCache[file.fileId];
      }
      if (_activeDownloads.containsKey(file.fileId)) {
        return _activeDownloads[file.fileId];
      }

      final downloadFuture = () async {
        try {
          final bytes = await _telegram.downloadByFileId(file.thumbnailFileId!);
          _webCache[file.fileId] = bytes;
          return bytes;
        } catch (e) {
          AppLogger.e('Failed to download web thumbnail: $e',
              tag: 'ThumbnailRepository');
          return null;
        } finally {
          _activeDownloads.remove(file.fileId);
        }
      }();

      _activeDownloads[file.fileId] = downloadFuture;
      return downloadFuture;
    } else {
      final cachedPath = await ThumbnailHelper.cachedThumbnailPath(file.fileId);
      if (cachedPath != null) return cachedPath;

      if (_activeDownloads.containsKey(file.fileId)) {
        return _activeDownloads[file.fileId];
      }

      final downloadFuture = () async {
        try {
          final bytes = await _telegram.downloadByFileId(file.thumbnailFileId!);
          return ThumbnailHelper.cacheThumbnail(file.fileId, bytes);
        } catch (e) {
          AppLogger.e('Failed to download native thumbnail: $e',
              tag: 'ThumbnailRepository');
          return null;
        } finally {
          _activeDownloads.remove(file.fileId);
        }
      }();

      _activeDownloads[file.fileId] = downloadFuture;
      return downloadFuture;
    }
  }
}
