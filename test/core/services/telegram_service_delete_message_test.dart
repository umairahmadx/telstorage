/*
 * File: telegram_service_delete_message_test.dart
 * Description: Tests verifying Telegram deleteMessage gracefully handles
 * "message can't be deleted" HTTP 400 responses (bot lacks delete rights
 * or message is too old) without throwing.
 */

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';

void main() {
  group('TelegramService deleteMessage graceful handling tests', () {
    setUp(() {
      TelegramRateLimiter.instance.reset();
    });

    tearDown(() {
      TelegramRateLimiter.instance.reset();
    });

    test(
        'TC-01: HTTP 400 "message can'\''t be deleted" returns without throwing',
        () async {
      int requestCount = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCount++;
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 400,
                  statusMessage: 'Bad Request',
                  data: {'description': "message can't be deleted"},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final service = TelegramService(dio: dio);
      await service.init('test_token', '-1001234567890');

      // Should complete without throwing — the error is swallowed as a warning.
      await service.deleteMessage(6410);

      expect(requestCount, equals(1),
          reason: 'deleteMessage should make exactly one API call');
    });

    test(
        'TC-02: HTTP 400 "message to delete not found" still returns without throwing',
        () async {
      int requestCount = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCount++;
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 400,
                  statusMessage: 'Bad Request',
                  data: {'description': 'message to delete not found'},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final service = TelegramService(dio: dio);
      await service.init('test_token', '-1001234567890');

      await service.deleteMessage(6465);

      expect(requestCount, equals(1),
          reason: 'deleteMessage should make exactly one API call');
    });

    test('TC-03: HTTP 400 with an unrelated description still logs a warning',
        () async {
      int requestCount = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requestCount++;
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 400,
                  statusMessage: 'Bad Request',
                  data: {'description': 'some other error'},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final service = TelegramService(dio: dio);
      await service.init('test_token', '-1001234567890');

      // Should not throw — unexpected 400s are logged as warnings and swallowed.
      await service.deleteMessage(9999);

      expect(requestCount, equals(1));
    });
  });
}