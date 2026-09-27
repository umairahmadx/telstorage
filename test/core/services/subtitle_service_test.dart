/*
 * File: subtitle_service_test.dart
 * Description: Unit tests for SubtitleService verifying query cleaning, delay formatting, API key header injection, ISP block detection, and download payload format.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/subtitle_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubtitleService Tests', () {
    test('cleanTitleForSearch strips extension, quality tags and codecs', () {
      const raw = 'Avatar.The.Way.of.Water.2022.1080p.BluRay.x264-SPARKS.mp4';
      final cleaned = SubtitleService.cleanTitleForSearch(raw);
      expect(cleaned, equals('Avatar The Way of Water 2022'));
    });

    test('cleanTitleForSearch handles clean movie names with spaces', () {
      const raw = 'Inception (2010) [2160p] [4k] [HEVC].mkv';
      final cleaned = SubtitleService.cleanTitleForSearch(raw);
      expect(cleaned, contains('Inception'));
    });

    test('formatDelay returns positive and negative ms strings', () {
      expect(SubtitleService.formatDelay(const Duration(milliseconds: 500)), equals('+500 ms'));
      expect(SubtitleService.formatDelay(const Duration(milliseconds: -250)), equals('-250 ms'));
      expect(SubtitleService.formatDelay(Duration.zero), equals('0 ms'));
    });

    test('searchSubtitles uses dotenv OPENSUBTITLES_API_KEY when no apiKey is passed', () async {
      dotenv.testLoad(fileInput: 'OPENSUBTITLES_API_KEY=test_api_key_123');

      String? capturedApiKey;
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedApiKey = options.headers['Api-Key'] as String?;
          handler.resolve(Response(
            requestOptions: options,
            data: {'data': []},
            statusCode: 200,
          ));
        },
      ));

      final service = SubtitleService(dio: dio);
      await service.searchSubtitles(query: 'Inception', language: 'en');

      expect(capturedApiKey, equals('test_api_key_123'));
    });

    test('searchSubtitles throws SubtitleIspBlockedException on ISP court-order HTML response', () async {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            data: '<iframe src="https://www.airtel.in/court-orders/ "></iframe>',
            statusCode: 200,
            headers: Headers.fromMap({'content-type': ['text/html']}),
          ));
        },
      ));

      final service = SubtitleService(dio: dio);
      expect(
        () => service.searchSubtitles(query: 'Inception', language: 'en'),
        throwsA(isA<SubtitleIspBlockedException>()),
      );
    });

    test('downloadOpenSubtitle sends POST to /api/v1/download with file_id body and Api-Key', () async {
      dotenv.testLoad(fileInput: 'OPENSUBTITLES_API_KEY=test_key_456');

      String? capturedUrl;
      dynamic capturedData;
      String? capturedApiKey;

      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains('/api/v1/download')) {
            capturedUrl = options.path;
            capturedData = options.data;
            capturedApiKey = options.headers['Api-Key'] as String?;
            handler.resolve(Response(
              requestOptions: options,
              data: {'link': 'https://mock.download.com/sub.srt'},
              statusCode: 200,
            ));
          } else if (options.path.contains('mock.download.com')) {
            handler.resolve(Response(
              requestOptions: options,
              data: ResponseBody.fromBytes(Uint8List(0), 200),
              statusCode: 200,
            ));
          }
        },
      ));

      final service = SubtitleService(dio: dio);
      await service.downloadOpenSubtitle(
        fileId: 7890,
        downloadUrl: 'https://api.opensubtitles.com/api/v1/download/7890',
        customSaveDir: Directory.systemTemp.path,
      );

      expect(capturedUrl, equals('https://api.opensubtitles.com/api/v1/download'));
      expect(capturedData, equals({'file_id': 7890}));
      expect(capturedApiKey, equals('test_key_456'));
    });
  });
}
