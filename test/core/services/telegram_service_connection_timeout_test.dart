/*
 * File: telegram_service_connection_timeout_test.dart
 * Description: Unit tests validating TelegramService retry behavior on
 * Dio connection timeouts (e.g. spotty Android mobile networks to
 * api.telegram.org).
 */

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';

void main() {
  group('TelegramService connection timeout retry tests', () {
    setUp(() {
      TelegramRateLimiter.instance.reset();
    });

    tearDown(() {
      TelegramRateLimiter.instance.reset();
    });

    test(
        'TC-01: getPinnedMessageId retries on connection timeout and succeeds on recovery',
        () async {
      int getChatAttempts = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/getChat')) {
              getChatAttempts++;
              if (getChatAttempts == 1) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 408,
                    ),
                    type: DioExceptionType.connectionTimeout,
                    error: SocketException(
                      'Connection timed out',
                      address: 'api.telegram.org',
                      port: 443,
                    ),
                  ),
                );
                return;
              } else {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {
                      'ok': true,
                      'result': {'pinned_message': {'message_id': 7777}},
                    },
                  ),
                );
                return;
              }
            }
            handler.next(options);
          },
        ),
      );

      final service = TelegramService(dio: dio);
      await service.init('dummy_token', '-1001234567890');

      final pinnedId = await service.getPinnedMessageId();

      expect(getChatAttempts, equals(2),
          reason: 'getPinnedMessageId should retry after connection timeout');
      expect(pinnedId, equals(7777));
    });

    test(
        'TC-02: getPinnedMessageId throws after exhausting all retries on persistent connection timeout',
        () async {
      int getChatAttempts = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/getChat')) {
              getChatAttempts++;
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 408,
                  ),
                  type: DioExceptionType.connectionTimeout,
                  error: SocketException(
                    'Connection timed out',
                    address: 'api.telegram.org',
                    port: 443,
                  ),
                ),
              );
              return;
            }
            handler.next(options);
          },
        ),
      );

      final service = TelegramService(dio: dio);
      await service.init('dummy_token', '-1001234567890');

      await expectLater(
        service.getPinnedMessageId(),
        throwsA(isA<DioException>()),
      );

      expect(getChatAttempts, equals(3),
          reason: 'getPinnedMessageId should make 3 attempts before giving up');
    });
  });
}