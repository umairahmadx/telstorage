/*
 * File: error_log_service_test.dart
 * Description: Unit tests for ErrorLogService ring buffer, persistence, and export functionality.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/models/error_log_record.dart';
import 'package:telstorage/core/services/error_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box testBox;
  late ErrorLogService service;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_svc_');
    Hive.init(tempDir.path);
    testBox = await Hive.openBox('test_error_logs_box');
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
    service = ErrorLogService.withBox(testBox);
  });

  group('ErrorLogService', () {
    test('logs error, warning, info and updates reactive notifier', () async {
      await service.logError('Download timed out',
          tag: 'DownloadQueue', error: 'TimeoutException');
      await service.logWarning('Approaching rate limit',
          tag: 'TelegramRateLimiter');
      await service.logInfo('Sync cycle started', tag: 'SyncService');

      final logs = service.logsNotifier.value;
      expect(logs.length, equals(3));
      expect(logs[0].level, equals(ErrorLogLevel.error));
      expect(logs[0].message, equals('Download timed out'));
      expect(logs[0].tag, equals('DownloadQueue'));
      expect(logs[0].errorDetails, equals('TimeoutException'));

      expect(logs[1].level, equals(ErrorLogLevel.warning));
      expect(logs[1].message, equals('Approaching rate limit'));

      expect(logs[2].level, equals(ErrorLogLevel.info));
      expect(logs[2].message, equals('Sync cycle started'));
    });

    test('enforces FIFO limit of 200 items', () async {
      for (int i = 0; i < 205; i++) {
        await service.logInfo('Event $i', tag: 'TestTag');
      }

      expect(service.logsNotifier.value.length,
          equals(ErrorLogService.maxLogCapacity));
      expect(service.logsNotifier.value.first.message, equals('Event 5'));
      expect(service.logsNotifier.value.last.message, equals('Event 204'));
      expect(testBox.length, equals(ErrorLogService.maxLogCapacity));
    });

    test('clears logs properly in memory and storage', () async {
      await service.logError('Temporary error', tag: 'Test');
      expect(service.logsNotifier.value.length, equals(1));

      await service.clearLogs();
      expect(service.logsNotifier.value.isEmpty, isTrue);
      expect(testBox.isEmpty, isTrue);
    });

    test('exports diagnostic report text containing log lines and headers',
        () async {
      await service.logError('Telegram 401 Unauthorized',
          tag: 'TelegramService',
          error: 'Bot token revoked',
          stackTrace: '#0 TelegramService.auth');

      final report = service.exportDiagnosticReport();
      expect(report, contains('TelStorage Diagnostic Report'));
      expect(report, contains('Telegram 401 Unauthorized'));
      expect(report, contains('[ERROR]'));
      expect(report, contains('[TelegramService]'));
      expect(report, contains('Bot token revoked'));
      expect(report, contains('#0 TelegramService.auth'));
    });
  });
}
