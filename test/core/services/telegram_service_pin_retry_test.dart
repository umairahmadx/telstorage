/*
 * File: telegram_service_pin_retry_test.dart
 * Description: Unit tests validating TelegramService pin, getPinnedMessage, and unpin operations under HTTP 429 rate limiting and admin permission errors.
 */

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';

void main() {
  group('TelegramService Pin & 429 Rate Limiting Tests', () {
    setUp(() {
      TelegramRateLimiter.instance.reset();
    });

    tearDown(() {
      TelegramRateLimiter.instance.reset();
    });

    test(
        'TC-01: pinMessage handles HTTP 429 by reporting backoff to rate limiter and retrying successfully',
        () async {
      int pinAttempts = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/pinChatMessage')) {
              pinAttempts++;
              if (pinAttempts == 1) {
                handler.reject(
                  DioException(
                    requestOptions: options,
                    response: Response(
                      requestOptions: options,
                      statusCode: 429,
                      data: {
                        'ok': false,
                        'error_code': 429,
                        'description': 'Too Many Requests: retry after 1',
                        'parameters': {'retry_after': 1},
                      },
                    ),
                    type: DioExceptionType.badResponse,
                  ),
                );
                return;
              } else {
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: 200,
                    data: {'ok': true, 'result': true},
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

      await service.pinMessage(1001);

      expect(pinAttempts, equals(2),
          reason: 'pinMessage should retry after encountering HTTP 429');
    });

    test(
        'TC-02: pinMessage throws descriptive permission error immediately on admin rights failure without retrying',
        () async {
      int pinAttempts = 0;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/pinChatMessage')) {
              pinAttempts++;
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 400,
                    data: {
                      'ok': false,
                      'error_code': 400,
                      'description':
                          'Bad Request: not enough rights to pin a message',
                    },
                  ),
                  type: DioExceptionType.badResponse,
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
        service.pinMessage(1001),
        throwsA(
          predicate((e) =>
              e is TelegramPermissionException &&
              e.toString().contains('Bot needs admin permission to pin messages')),
        ),
      );

      expect(pinAttempts, equals(1),
          reason: 'Permission errors must fail fast on attempt 1');
    });

    test(
        'TC-03: getPinnedMessageId retries on HTTP 429 and returns pinned message ID on recovery',
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
                      statusCode: 429,
                      data: {
                        'ok': false,
                        'error_code': 429,
                        'description': 'Too Many Requests: retry after 1',
                        'parameters': {'retry_after': 1},
                      },
                    ),
                    type: DioExceptionType.badResponse,
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
                      'result': {
                        'pinned_message': {'message_id': 7777}
                      },
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

      expect(getChatAttempts, equals(2));
      expect(pinnedId, equals(7777));
    });

    test('TC-04: unpinAllMessages reports 429 to rate limiter without crashing',
        () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.endsWith('/unpinAllChatMessages')) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  response: Response(
                    requestOptions: options,
                    statusCode: 429,
                    data: {
                      'ok': false,
                      'error_code': 429,
                      'description': 'Too Many Requests: retry after 3',
                      'parameters': {'retry_after': 3},
                    },
                  ),
                  type: DioExceptionType.badResponse,
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

      // Should complete gracefully without throwing
      await service.unpinAllMessages();

      expect(TelegramRateLimiter.instance.isPaused, isTrue,
          reason: '429 from unpinAllMessages must pause rate limiter');
    });
  });
}
