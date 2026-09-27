/*
 * File: lyrics_service.dart
 * Description: Lyrics resolution service supporting LRCLIB REST fetching, local file picking, title cleaning, and offline disk caching.
 */

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/lyric_line.dart';
import '../utils/app_logger.dart';

/// Cleaned metadata extracted from an audio file's name.
class CleanedAudioMeta {
  /// Cleaned track name.
  final String trackName;

  /// Optional artist name if detected (e.g. from "Artist - Track").
  final String? artistName;

  const CleanedAudioMeta({
    required this.trackName,
    this.artistName,
  });
}

/// Service handling online lyrics retrieval from LRCLIB, local file imports, and disk caching.
class LyricsService {
  final Dio _dio;
  Directory? _cacheDirOverride;

  LyricsService({Dio? dio}) : _dio = dio ?? Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      headers: {
        'User-Agent': 'TelStorage Music Player v1.0 (https://github.com/umairahmadx/telstorage)',
      },
    ),
  );

  static final LyricsService instance = LyricsService();

  /// Overrides the cache directory for isolated unit testing.
  void setCacheDirForTesting(Directory? dir) {
    _cacheDirOverride = dir;
  }

  /// Extracts clean track and optional artist names from an audio filename.
  static CleanedAudioMeta cleanTitleAndArtist(String filename) {
    // 1. Remove file extensions (.mp3, .m4a, .flac, etc.)
    var clean = filename.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,5}$'), '');

    // 2. Remove common track numbers at start like "01. " or "01 - "
    clean = clean.replaceAll(RegExp(r'^\d{1,3}[\.\s\-]+'), '');

    // 3. Remove metadata brackets e.g. [Official Video], (Lyrics), (Audio), [HQ]
    clean = clean.replaceAll(
      RegExp(
        r'[\(\[][\w\s\-]*(?:official|video|audio|lyrics|hd|hq|remastered|version|feat|ft\.)[\w\s\-]*[\)\]]',
        caseSensitive: false,
      ),
      '',
    );

    // 4. Split by artist/title separator if present (e.g. "Artist - Title")
    if (clean.contains(' - ')) {
      final parts = clean.split(' - ');
      final artist = parts.first.trim();
      final track = parts.sublist(1).join(' - ').trim();
      if (artist.isNotEmpty && track.isNotEmpty) {
        return CleanedAudioMeta(trackName: _sanitize(track), artistName: _sanitize(artist));
      }
    }

    return CleanedAudioMeta(trackName: _sanitize(clean));
  }

  static String _sanitize(String text) {
    return text
        .replaceAll(RegExp(r'[\_\.\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<Directory> _getLyricsCacheDir() async {
    if (_cacheDirOverride != null) return _cacheDirOverride!;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/lyrics_cache');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Returns cached LRC content if present on disk.
  Future<String?> getCachedLyrics(String identifier) async {
    try {
      final dir = await _getLyricsCacheDir();
      final sanitizedId = identifier.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final file = File('${dir.path}/$sanitizedId.lrc');
      if (file.existsSync()) {
        return await file.readAsString();
      }
    } catch (e) {
      AppLogger.w('Failed to read cached lyrics for $identifier: $e', tag: 'LyricsService');
    }
    return null;
  }

  /// Caches raw LRC content to local disk for offline playback.
  Future<void> cacheLyrics(String identifier, String lrcContent) async {
    try {
      final dir = await _getLyricsCacheDir();
      final sanitizedId = identifier.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final file = File('${dir.path}/$sanitizedId.lrc');
      await file.writeAsString(lrcContent, flush: true);
    } catch (e) {
      AppLogger.w('Failed to write cached lyrics for $identifier: $e', tag: 'LyricsService');
    }
  }

  /// Fetches synchronized or plain lyrics from LRCLIB with disk cache fallback.
  Future<List<LyricLine>> fetchLyrics({
    required String filename,
    Duration? duration,
    String? fileId,
  }) async {
    final cacheKey = fileId ?? filename;

    // 1. Check local cache
    final cached = await getCachedLyrics(cacheKey);
    if (cached != null && cached.trim().isNotEmpty) {
      final parsed = LyricLine.parseLrc(cached);
      if (parsed.isNotEmpty) return parsed;
      return LyricLine.parsePlain(cached);
    }

    // 2. Resolve query tokens
    final meta = cleanTitleAndArtist(filename);
    if (meta.trackName.isEmpty) return const [];

    try {
      // 3. Try exact /api/get
      final queryParams = <String, dynamic>{
        'track_name': meta.trackName,
      };
      if (meta.artistName != null && meta.artistName!.isNotEmpty) {
        queryParams['artist_name'] = meta.artistName;
      }
      if (duration != null && duration.inSeconds > 0) {
        queryParams['duration'] = duration.inSeconds;
      }

      Response response;
      try {
        response = await _dio.get(
          'https://lrclib.net/api/get',
          queryParameters: queryParams,
        );
      } on DioException catch (dioErr) {
        if (dioErr.response?.statusCode == 404) {
          // Fallback to search endpoint
          response = await _dio.get(
            'https://lrclib.net/api/search',
            queryParameters: {'q': meta.artistName != null ? '${meta.artistName} ${meta.trackName}' : meta.trackName},
          );
        } else {
          rethrow;
        }
      }

      String? lrcText;
      if (response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        lrcText = (data['syncedLyrics'] as String?) ?? (data['plainLyrics'] as String?);
      } else if (response.data is List && (response.data as List).isNotEmpty) {
        // From search results list, find first with syncedLyrics or plainLyrics
        for (final item in response.data as List) {
          if (item is Map<String, dynamic>) {
            final synced = item['syncedLyrics'] as String?;
            if (synced != null && synced.trim().isNotEmpty) {
              lrcText = synced;
              break;
            }
            final plain = item['plainLyrics'] as String?;
            if (plain != null && plain.trim().isNotEmpty && lrcText == null) {
              lrcText = plain;
            }
          }
        }
      }

      if (lrcText != null && lrcText.trim().isNotEmpty) {
        await cacheLyrics(cacheKey, lrcText);
        final parsed = LyricLine.parseLrc(lrcText);
        if (parsed.isNotEmpty) return parsed;
        return LyricLine.parsePlain(lrcText);
      }
    } catch (e) {
      AppLogger.w('Failed to fetch online lyrics for ${meta.trackName}: $e', tag: 'LyricsService');
    }

    return const [];
  }

  /// Opens system file picker for the user to select a local .lrc or .txt file.
  Future<List<LyricLine>?> pickLocalLyricsFile({String? cacheKey}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['lrc', 'txt'],
      );

      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        if (file.existsSync()) {
          final content = await file.readAsString();
          if (cacheKey != null && content.isNotEmpty) {
            await cacheLyrics(cacheKey, content);
          }
          final parsed = LyricLine.parseLrc(content);
          if (parsed.isNotEmpty) return parsed;
          return LyricLine.parsePlain(content);
        }
      }
    } catch (e) {
      AppLogger.e('Failed to pick local lyrics file: $e', tag: 'LyricsService');
    }
    return null;
  }
}
