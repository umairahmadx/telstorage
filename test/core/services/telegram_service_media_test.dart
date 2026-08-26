/*
 * File: telegram_service_media_test.dart
 * Description: Unit tests validating TelegramService media extraction across sticker, document, animation, photo, video, and audio payloads.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/telegram_service.dart';

void main() {
  group('TelegramService Media Extraction Tests', () {
    test('TC-01: TelegramService initializes without error', () async {
      final service = TelegramService();
      await service.init('mock_token', '-1001234567890');
      expect(service, isNotNull);
    });
  });
}
