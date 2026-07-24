import 'dart:collection';
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
  static const int _maxWebCacheSize = 200;
  final LinkedHashMap<String, Uint8List> _webCache = LinkedHashMap();

  ThumbnailRepository(this._telegram);

  void clearWebCache() {
    _webCache.clear();
    _activeDownloads.clear();
  }

  void _addToWebCache(String fileId, Uint8List bytes) {
    if (_webCache.containsKey(fileId)) {
      _webCache.remove(fileId);
    } else if (_webCache.length >= _maxWebCacheSize) {
      _webCache.remove(_webCache.keys.first);
    }
    _webCache[fileId] = bytes;
  }

  Future<dynamic> getThumbnailData(FileRecord file) async {
    if (file.thumbnailFileId == null) return null;

    if (kIsWeb) {
      if (_webCache.containsKey(file.fileId)) {
        final bytes = _webCache.remove(file.fileId)!;
        _webCache[file.fileId] = bytes; // MRU update
        return bytes;
      }
      if (_activeDownloads.containsKey(file.fileId)) {
        return _activeDownloads[file.fileId];
      }

      final downloadFuture = () async {
        try {
          final bytes = await _telegram.downloadByFileId(file.thumbnailFileId!);
          _addToWebCache(file.fileId, bytes);
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
