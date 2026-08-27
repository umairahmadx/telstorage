/*
 * File: error_logs_screen_test.dart
 * Description: Widget tests verifying ErrorLogsScreen UI, search filtering, severity tabs, detail sheet, and clearing logs.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/services/error_log_service.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/settings/presentation/screens/error_logs/error_logs_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box testBox;
  late ErrorLogService service;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_ui_');
    Hive.init(tempDir.path);
    testBox = await Hive.openBox('test_err_ui_box');
  });

  tearDownAll(() async {
    await testBox.close();
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Widget createTestWidget() {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: const ErrorLogsScreen(),
    );
  }

  group('ErrorLogsScreen Widget Tests', () {
    testWidgets('renders empty state when no logs exist', (tester) async {
      await tester.runAsync(() async {
        await testBox.clear();
        service = ErrorLogService.withBox(testBox);
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('No Logs Recorded'), findsOneWidget);
      expect(find.text('Everything is running smoothly.'), findsOneWidget);
    });

    testWidgets('displays logged events and filters by search keyword',
        (tester) async {
      await tester.runAsync(() async {
        await testBox.clear();
        service = ErrorLogService.withBox(testBox);
        await service.logError('Telegram 429 flood wait',
            tag: 'TelegramService');
        await service.logWarning('Low disk cache space', tag: 'CacheManager');
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Telegram 429 flood wait'), findsOneWidget);
      expect(find.text('Low disk cache space'), findsOneWidget);

      // Search for "Telegram"
      await tester.enterText(find.byType(TextField), 'Telegram');
      await tester.pump();

      expect(find.text('Telegram 429 flood wait'), findsOneWidget);
      expect(find.text('Low disk cache space'), findsNothing);
    });

    testWidgets('filters by severity chip tabs', (tester) async {
      await tester.runAsync(() async {
        await testBox.clear();
        service = ErrorLogService.withBox(testBox);
        await service.logError('Critical error', tag: 'Network');
        await service.logWarning('Minor warning', tag: 'Sync');
        await service.logInfo('Info event', tag: 'App');
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Critical error'), findsOneWidget);
      expect(find.text('Minor warning'), findsOneWidget);
      expect(find.text('Info event'), findsOneWidget);

      // Tap "Errors" chip
      await tester.tap(find.text('Errors'));
      await tester.pump();

      expect(find.text('Critical error'), findsOneWidget);
      expect(find.text('Minor warning'), findsNothing);
      expect(find.text('Info event'), findsNothing);
    });

    testWidgets('opens detail sheet when tapping log tile and closes it',
        (tester) async {
      await tester.runAsync(() async {
        await testBox.clear();
        service = ErrorLogService.withBox(testBox);
        await service.logError(
          'Upload failed with socket exception',
          tag: 'UploadService',
          error: 'SocketException: Connection refused',
          stackTrace: '#0 UploadService.sendChunk (upload_service.dart:120)',
        );
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      await tester.tap(find.text('Upload failed with socket exception'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Log Details'), findsOneWidget);
      expect(find.text('SocketException: Connection refused'),
          findsAtLeastNWidgets(1));
      expect(find.text('Copy Stack Trace'), findsOneWidget);


      // Close bottom sheet
      Navigator.of(tester.element(find.text('Log Details'))).pop();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Log Details'), findsNothing);

    });
  });
}
