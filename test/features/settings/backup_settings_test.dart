/*
 * File: backup_settings_test.dart
 * Description: Widget tests for the AUTO BACKUP settings card: rendering,
 * master-switch persistence, and live status line.
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/settings/presentation/screens/settings/backup/backup_screen.dart';
import 'package:telstorage/features/settings/presentation/screens/settings/widgets/settings_backup_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // google_fonts fetches Inter from fonts.gstatic.com at runtime; in widget
  // tests there is no HTTP mock, so each fetch stalls for minutes and the
  // first pump never settles. Disable fetching: styles fall back to the
  // bundled test font with zero network.
  GoogleFonts.config.allowRuntimeFetching = false;

  late Directory tempDir;
  late Box<BackupRule> rulesBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_settings_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(BackupRuleAdapter());
    }
    rulesBox = await Hive.openBox<BackupRule>(AppConstants.backupRulesBox);
    await rulesBox.clear();
    await rulesBox.put(
      'camera',
      BackupRule(id: 'camera', albumName: 'Camera', enabled: false),
    );
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Widget createTestWidget() {
    return MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [AppTheme.darkColorsExtension],
      ),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: SettingsBackupCard(),
        ),
      ),
    );
  }

  group('SettingsBackupCard Widget Tests', () {
    testWidgets('renders title and master switch, persists toggle',
        (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Auto Backup'), findsOneWidget);
      expect(rulesBox.get('camera')!.enabled, isFalse);

      await tester.runAsync(() async {
        await tester.tap(find.byType(Switch));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(rulesBox.get('camera')!.enabled, isTrue);
    });

    testWidgets('shows the destination copy', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.textContaining('root/Backup/Camera'), findsWidgets);
    });
  });

  testWidgets('backup screen exposes one context-aware manual action',
      (tester) async {
    await tester.runAsync(() async {
      final rule = rulesBox.get('camera')!..enabled = true;
      await rule.save();
    });
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [AppTheme.darkColorsExtension],
      ),
      home: const BackupScreen(),
    ));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Back up existing photos'),
      250,
      scrollable: find.byType(Scrollable),
    );

    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.widgetWithText(ElevatedButton, 'Back up existing photos'),
        findsOneWidget);
  });
}
