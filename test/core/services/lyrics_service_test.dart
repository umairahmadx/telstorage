/*
 * File: lyrics_service_test.dart
 * Description: Unit tests for LyricsService testing filename cleaning, LRCLIB REST mocking, and offline disk caching.
 */

import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/lyrics_service.dart';

class MockAdapter implements HttpClientAdapter {
  final Map<String, dynamic> Function(RequestOptions options) handler;

  MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final res = handler(options);
    final status = res['status'] as int? ?? 200;
    final body = res['body'] as String? ?? '';
    return ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lyrics_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('LyricsService Unit Tests', () {
    test('cleanTitleAndArtist parses track and artist correctly', () {
      final meta1 = LyricsService.cleanTitleAndArtist('Coldplay - Yellow.mp3');
      expect(meta1.artistName, equals('Coldplay'));
      expect(meta1.trackName, equals('Yellow'));

      final meta2 = LyricsService.cleanTitleAndArtist('01. Queen - Bohemian Rhapsody (Official Video) [HQ].flac');
      expect(meta2.artistName, equals('Queen'));
      expect(meta2.trackName, equals('Bohemian Rhapsody'));

      final meta3 = LyricsService.cleanTitleAndArtist('Imagine.m4a');
      expect(meta3.artistName, isNull);
      expect(meta3.trackName, equals('Imagine'));
    });

    test('cacheLyrics and getCachedLyrics persist lyrics to disk', () async {
      final service = LyricsService();
      service.setCacheDirForTesting(tempDir);

      const testLrc = '[00:01.00]Hello world';
      await service.cacheLyrics('test_song_1', testLrc);

      final cached = await service.getCachedLyrics('test_song_1');
      expect(cached, equals(testLrc));

      final notFound = await service.getCachedLyrics('non_existent');
      expect(notFound, isNull);
    });

    test('fetchLyrics returns cached lyrics without network call', () async {
      final service = LyricsService();
      service.setCacheDirForTesting(tempDir);

      const cachedLrc = '[00:10.00]Cached lyric line';
      await service.cacheLyrics('song_123', cachedLrc);

      final lyrics = await service.fetchLyrics(
        filename: 'song_123.mp3',
        fileId: 'song_123',
      );

      expect(lyrics.length, equals(1));
      expect(lyrics.first.text, equals('Cached lyric line'));
    });

    test('fetchLyrics falls back to search endpoint when /api/get returns 404', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) {
        if (options.path.contains('/api/get')) {
          return {'status': 404, 'body': '{"message":"Not found"}'};
        } else if (options.path.contains('/api/search')) {
          return {
            'status': 200,
            'body': '[{"trackName":"Yellow","syncedLyrics":"[00:05.00]Look at the stars"}]',
          };
        }
        return {'status': 500, 'body': '{}'};
      });

      final service = LyricsService(dio: dio);
      service.setCacheDirForTesting(tempDir);

      final lyrics = await service.fetchLyrics(filename: 'Coldplay - Yellow.mp3');
      expect(lyrics.length, equals(1));
      expect(lyrics.first.text, equals('Look at the stars'));
      expect(lyrics.first.timestamp, equals(const Duration(seconds: 5)));
    });

    test('fetchLyrics handles network errors gracefully without throwing', () async {
      final dio = Dio();
      dio.httpClientAdapter = MockAdapter((options) {
        return {'status': 500, 'body': 'Server error'};
      });

      final service = LyricsService(dio: dio);
      service.setCacheDirForTesting(tempDir);

      final lyrics = await service.fetchLyrics(filename: 'Broken Network.mp3');
      expect(lyrics, isEmpty);
    });
  });
}
