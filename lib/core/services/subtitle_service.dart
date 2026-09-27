/*
 * File: subtitle_service.dart
 * Description: Subtitle resolution service handling OpenSubtitles REST search, local file picking, direct URL downloads, and timing offsets.
 */

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

/// Exception thrown when ISP, firewall, or regional court order blocks access to subtitle endpoints.
class SubtitleIspBlockedException implements Exception {
  final String message;
  const SubtitleIspBlockedException([
    this.message =
        'OpenSubtitles is blocked by your internet provider (court order). Please enable VPN or Private DNS (1.1.1.1) to unblock.',
  ]);

  @override
  String toString() => message;
}

/// Represents a subtitle search result item from OpenSubtitles.
class SubtitleSearchResult {
  final String id;
  final int? fileId;
  final String title;
  final String language;
  final String downloadUrl;
  final int downloadCount;

  const SubtitleSearchResult({
    required this.id,
    this.fileId,
    required this.title,
    required this.language,
    required this.downloadUrl,
    required this.downloadCount,
  });
}

/// Service handling subtitle search, download, local file picking, and offset formatting.
class SubtitleService {
  final Dio _dio;

  SubtitleService({Dio? dio}) : _dio = dio ?? Dio();

  static final SubtitleService instance = SubtitleService();

  /// Resolves the OpenSubtitles API key from explicit parameter or .env fallback.
  String _resolveApiKey(String? explicitKey) {
    if (explicitKey != null && explicitKey.trim().isNotEmpty) {
      return explicitKey.trim();
    }
    if (dotenv.isInitialized && dotenv.env['OPENSUBTITLES_API_KEY'] != null) {
      return dotenv.env['OPENSUBTITLES_API_KEY']!.trim();
    }
    return '';
  }

  /// Cleans a video filename by removing file extensions, release group tags, and resolution info.
  static String cleanTitleForSearch(String filename) {
    var name = filename.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,4}$'), '');
    name = name.replaceAll(RegExp(r'-[a-zA-Z0-9]+$'), '');
    name = name.replaceAll(RegExp(r'[\.\_\-]'), ' ');
    name = name.replaceAll(
      RegExp(r'\b(1080p|720p|4k|2160p|480p|bluray|webrip|web-dl|x264|x265|hevc|aac|dts|remux|hdr)\b',
          caseSensitive: false),
      '',
    );
    name = name.replaceAll(RegExp(r'[\[\]]'), ' ');
    return name.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Formats a subtitle delay duration into human-readable millisecond offset string.
  static String formatDelay(Duration delay) {
    final ms = delay.inMilliseconds;
    if (ms > 0) return '+$ms ms';
    if (ms < 0) return '$ms ms';
    return '0 ms';
  }

  /// Searches OpenSubtitles REST API for matching subtitles.
  Future<List<SubtitleSearchResult>> searchSubtitles({
    required String query,
    String? language,
    String? apiKey,
  }) async {
    final cleaned = cleanTitleForSearch(query);
    if (cleaned.isEmpty) return const [];

    final key = _resolveApiKey(apiKey);
    final headers = <String, String>{
      'User-Agent': 'TelStorage v1.0',
      'Accept': 'application/json',
    };
    if (key.isNotEmpty) {
      headers['Api-Key'] = key;
    }

    final res = await _dio.get(
      'https://api.opensubtitles.com/api/v1/subtitles',
      queryParameters: {
        'query': cleaned,
        if (language != null && language.isNotEmpty && language != 'all')
          'languages': language,
      },
      options: Options(headers: headers),
    );

    if (res.data is String) {
      final str = (res.data as String).toLowerCase();
      if (str.contains('court-orders') ||
          str.contains('airtel.in') ||
          str.contains('iframe') ||
          str.contains('<!doctype html>')) {
        throw const SubtitleIspBlockedException();
      }
      throw Exception('OpenSubtitles returned unexpected HTML response');
    }

    if (res.data is! Map) {
      return const [];
    }

    final data = res.data['data'] as List?;
    if (data == null) return const [];

    return data.map((item) {
      final attr = (item['attributes'] as Map<String, dynamic>?) ?? {};
      final files = attr['files'] as List?;
      final fileId = (files != null && files.isNotEmpty)
          ? (files[0]['file_id'] as num?)?.toInt()
          : null;
      final downloadLink = fileId != null
          ? 'https://api.opensubtitles.com/api/v1/download/$fileId'
          : '';

      return SubtitleSearchResult(
        id: item['id']?.toString() ?? '',
        fileId: fileId,
        title: (attr['release'] as String?)?.isNotEmpty == true
            ? attr['release'] as String
            : (attr['feature_details']?['title'] as String? ?? cleaned),
        language: (attr['language'] as String?) ?? 'en',
        downloadUrl: downloadLink,
        downloadCount: (attr['download_count'] as num?)?.toInt() ?? 0,
      );
    }).where((s) => s.downloadUrl.isNotEmpty).toList();
  }

  /// Prompts user to pick a local subtitle file from storage.
  Future<String?> pickLocalSubtitleFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'sub', 'ass', 'ssa'],
      );
      if (result == null || result.files.isEmpty) return null;
      return result.files.first.path;
    } catch (_) {
      return null;
    }
  }

  /// Downloads a subtitle from direct HTTP URL and saves it to local temporary cache.
  Future<String> fetchSubtitleFromUrl(String url, {String? customSaveDir}) async {
    final tempDirPath = customSaveDir ?? (await getTemporaryDirectory()).path;
    final ext = url.split('?').first.split('.').last.toLowerCase();
    final safeExt = ['srt', 'vtt', 'sub', 'ass', 'ssa'].contains(ext) ? ext : 'srt';
    final savePath = '$tempDirPath/sub_${DateTime.now().millisecondsSinceEpoch}.$safeExt';

    await _dio.download(url, savePath);
    return savePath;
  }

  /// Downloads an OpenSubtitles subtitle payload using the v1 download endpoint specification.
  Future<String> downloadOpenSubtitle({
    int? fileId,
    String? downloadUrl,
    String? apiKey,
    String? customSaveDir,
  }) async {
    final key = _resolveApiKey(apiKey);
    final headers = <String, String>{
      'User-Agent': 'TelStorage v1.0',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (key.isNotEmpty) {
      headers['Api-Key'] = key;
    }

    int? targetFileId = fileId;
    if (targetFileId == null && downloadUrl != null) {
      final lastSegment = downloadUrl.split('/').last;
      targetFileId = int.tryParse(lastSegment);
    }

    if (targetFileId == null) {
      throw Exception('Valid file_id required for OpenSubtitles download');
    }

    final res = await _dio.post(
      'https://api.opensubtitles.com/api/v1/download',
      data: {'file_id': targetFileId},
      options: Options(headers: headers),
    );

    if (res.data is String) {
      final str = (res.data as String).toLowerCase();
      if (str.contains('court-orders') || str.contains('airtel.in') || str.contains('iframe')) {
        throw const SubtitleIspBlockedException();
      }
      throw Exception('Unexpected response format when downloading subtitle');
    }

    final link = res.data['link'] as String?;
    if (link == null || link.isEmpty) {
      throw Exception('Failed to obtain download link from OpenSubtitles');
    }

    return await fetchSubtitleFromUrl(link, customSaveDir: customSaveDir);
  }
}
