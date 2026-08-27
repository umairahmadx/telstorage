/*
 * File: app_logger_error_interception_test.dart
 * Description: Tests verifying AppLogger automatically forwards errors and warnings to ErrorLogService.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/models/error_log_record.dart';
import 'package:telstorage/core/services/error_log_service.dart';
import 'package:telstorage/core/utils/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box testBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_log_');
    Hive.init(tempDir.path);
    testBox = await Hive.openBox('test_logger_int_box');
  });

  tearDownAll(() async {
    await testBox.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() async {
    await testBox.clear();
    ErrorLogService.withBox(testBox);
  });

  group('AppLogger Error Interception', () {
    test('AppLogger.e forwards to ErrorLogService with full context', () async {
      AppLogger.e(
        'Failed to fetch Telegram metadata',
        tag: 'TelegramService',
        error: '401 Unauthorized',
        stackTrace: StackTrace.current,
      );

      final logs = ErrorLogService.instance.logsNotifier.value;
      expect(
          logs.any((l) =>
              l.message == 'Failed to fetch Telegram metadata' &&
              l.level == ErrorLogLevel.error &&
              l.tag == 'TelegramService' &&
              l.errorDetails == '401 Unauthorized'),
          isTrue);
    });

    test('AppLogger.w forwards to ErrorLogService', () async {
      AppLogger.w(
        'Rate limit approaching threshold',
        tag: 'TelegramRateLimiter',
        error: 'Remaining: 1 request/sec',
      );

      final logs = ErrorLogService.instance.logsNotifier.value;
      expect(
          logs.any((l) =>
              l.message == 'Rate limit approaching threshold' &&
              l.level == ErrorLogLevel.warning &&
              l.tag == 'TelegramRateLimiter'),
          isTrue);
    });
  });
}
