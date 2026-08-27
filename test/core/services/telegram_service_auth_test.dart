/*
 * File: telegram_service_auth_test.dart
 * Description: Tests verifying Telegram 401 Unauthorized token revocation fail-fast handling and domain event firing.
 */

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/events/domain_event_bus.dart';
import 'package:telstorage/core/services/telegram_service.dart';

void main() {
  group('TelegramService 401 Unauthorized Token Revocation Tests', () {
    test(
        'TC-01: HTTP 401 throws TelegramAuthException and fires AuthTokenRevokedEvent without retrying',
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
                  statusCode: 401,
                  statusMessage: 'Unauthorized: bot token is invalid',
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final service = TelegramService(dio: dio);
      await service.init('invalid_token', '-1001234567890');

      AuthTokenRevokedEvent? capturedEvent;
      final subscription =
          DomainEventBus.instance.on<AuthTokenRevokedEvent>().listen((event) {
        capturedEvent = event;
      });

      expect(
        () => service.downloadByFileId('test_file_id'),
        throwsA(isA<TelegramAuthException>()),
      );

      await Future.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      expect(requestCount, equals(1),
          reason: '401 should fail fast and never retry');
      expect(capturedEvent, isNotNull,
          reason: 'AuthTokenRevokedEvent must be fired on HTTP 401');
    });
  });
}
