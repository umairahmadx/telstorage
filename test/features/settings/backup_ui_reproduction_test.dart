/*
 * File: backup_ui_reproduction_test.dart
 * Description: Automated reproduction test verifying UI status and SnackBar
 * feedback defects during backup failures and active runs.
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/services/auto_backup_scheduler.dart';
import 'package:telstorage/core/services/auto_backup_service.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/settings/presentation/screens/settings/backup/backup_screen.dart';
import 'package:telstorage/features/settings/presentation/screens/settings/widgets/settings_backup_card.dart';

class _MockUiBackupService extends AutoBackupService {
  BackupEligibility manualEligibility;

  _MockUiBackupService({
    required this.manualEligibility,
    required super.ledgerBox,
  }) : super(
          requestPermission: () async => true,
          hasPermission: () async => true,
          loadAlbums: () async => [],
          loadPage: (_, __, ___) async => [],
          isUnmetered: () async => true,
          isCharging: () async => true,
        );

  @override
  Future<Result<BackupEligibility>> isEligibleNowManual(
    BackupRule rule, {
    DateTime? now,
  }) async =>
      Success(manualEligibility);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  late Directory tempDir;
  late Box<BackupRule> rulesBox;
  late Box<bool> stateBox;
  late Box<BackupLedgerEntry> ledgerBox;
  late _MockUiBackupService mockService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_ui_repro_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(BackupRuleAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(BackupLedgerEntryAdapter());
    }
    rulesBox = await Hive.openBox<BackupRule>(AppConstants.backupRulesBox);
    stateBox = await Hive.openBox<bool>(AppConstants.autoBackupStateBox);
    ledgerBox =
        await Hive.openBox<BackupLedgerEntry>(AppConstants.backupLedgerBox);

    await rulesBox.clear();
    await stateBox.clear();
    await ledgerBox.clear();

    await rulesBox.put(
      'camera',
      BackupRule(id: 'camera', albumName: 'Camera', enabled: true),
    );

    mockService = _MockUiBackupService(
      manualEligibility:
          const BackupEligibility(BackupBlockReason.ready),
      ledgerBox: ledgerBox,
    );
    AutoBackupScheduler.instance.configureService(mockService);
  });

  tearDown(() async {
    AutoBackupScheduler.instance.runInProgressForTesting = false;
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('Backup UI Defect Reproduction', () {
    testWidgets(
        'SettingsBackupCard must display failure when lastResult is failed',
        (tester) async {
      await tester.runAsync(() async {
        final rule = rulesBox.get('camera')!;
        rule.lastResult = 'failed';
        rule.lastRunAt = DateTime.now();
        await rule.save();
      });

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [AppTheme.darkColorsExtension],
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsBackupCard(
              enablePolling: false,
              permissionChecker: () async => true,
              connectionChecker: () async => true,
              unmeteredChecker: () async => true,
              chargingChecker: () async => true,
            ),
          ),
        ),
      ));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(
        find.textContaining('failed'),
        findsOneWidget,
        reason:
            'SettingsBackupCard should indicate that the last backup failed',
      );
    });

    testWidgets(
        'BackupScreen displays accurate in-progress error message instead of generic ineligible text',
        (tester) async {
      AutoBackupScheduler.instance.runInProgressForTesting = true;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: const [AppTheme.darkColorsExtension],
        ),
        home: const BackupScreen(),
      ));
      await tester.pump();

      await tester.scrollUntilVisible(
        find.byType(ElevatedButton),
        250,
        scrollable: find.byType(Scrollable),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byType(ElevatedButton));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('already running'),
        findsOneWidget,
        reason:
            'BackupScreen must inform the user when a backup is already in progress',
      );
    });
  });
}
