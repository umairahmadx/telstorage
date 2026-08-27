/*
 * File: settings_tools_card_test.dart
 * Description: Widget tests validating SettingsToolsCard rendering and navigation to ErrorLogsScreen.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/services/error_log_service.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/settings/presentation/screens/settings/widgets/settings_tools_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box testBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_test_tools_');
    Hive.init(tempDir.path);
    testBox = await Hive.openBox('test_tools_err_box');
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

  Widget createTestWidget() {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: SettingsToolsCard(),
        ),
      ),
    );
  }

  group('SettingsToolsCard Widget Tests', () {
    testWidgets('renders Error & Diagnostic Logs tile', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Error & Diagnostic Logs'), findsOneWidget);
      expect(
          find.text('Inspect system warnings, network logs, and errors'),
          findsOneWidget);
    });

    testWidgets('tapping Error & Diagnostic Logs tile pushes ErrorLogsScreen',
        (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      await tester.tap(find.text('Error & Diagnostic Logs'));
      await tester.pumpAndSettle();

      expect(find.text('No Logs Recorded'), findsOneWidget);
      expect(find.text('Everything is running smoothly.'), findsOneWidget);
    });
  });
}
