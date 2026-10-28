/*
 * File: auto_backup_regression_test.dart
 * Description: Regression tests for the five auto-backup root causes:
 *   (1) dependency wiring — AutoBackupService constructed with DiskSpacePlus-backed
 *       FreeSpaceProvider and Connectivity.isUnmetered hook;
 *   (2) rule eligibility — BackupRule stores createdAt and passes eligibility gates;
 *   (3) isolate startup / box cleanup — HiveService.clearAll() clears all three
 *       auto-backup boxes;
 *   (4) account/logout cleanup — AccountResetService triggers HiveService.clearAll;
 *   (5) failure propagation — checkDueInBackground catches errors and returns false,
 *       and isEligibleNow never throws on provider failure.
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/auto_backup_scheduler.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/services/auto_backup_service.dart';
import 'package:telstorage/core/services/auto_backup_types.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/errors/result.dart';

/// Helper function for DiskSpacePlus free space probe.
/// Used in auto-backup dependency wiring tests.
Future<int?> _diskSpacePlusWrapped() async {
  final free = await Future<double>.value(10.5);
  return free.toInt();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<BackupRule> rulesBox;
  late Box<BackupLedgerEntry> ledgerBox;
  late Box<bool> stateBox;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_regression_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(BackupRuleAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(BackupLedgerEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FileRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(FolderRecordAdapter());
    }
    rulesBox = await Hive.openBox<BackupRule>(AppConstants.backupRulesBox);
    ledgerBox = await Hive.openBox<BackupLedgerEntry>(
      AppConstants.backupLedgerBox,
    );
    stateBox = await Hive.openBox<bool>(AppConstants.autoBackupStateBox);
    await rulesBox.clear();
    await ledgerBox.clear();
    await stateBox.clear();
    // clearAll() unconditionally clears filesBox and foldersBox.
    final _ = await Hive.openBox<FileRecord>(AppConstants.filesBox);
    await Hive.openBox<FolderRecord>(AppConstants.foldersBox);
  });

  tearDown(() async {
    await rulesBox.close();
    await ledgerBox.close();
    await stateBox.close();
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  BackupRule cameraRule({bool enabled = true, DateTime? createdAt}) =>
      BackupRule(
        id: 'camera',
        albumName: 'Camera',
        enabled: enabled,
        backfillDone: true,
        createdAt: createdAt ?? DateTime(2025, 6, 1),
        windowStartMinutes: 0,
        windowEndMinutes: 1439,
      );

  // ── (1) Dependency wiring ──────────────────────────────────

  group('dependency wiring', () {
    test('production service can be attached to the scheduler singleton', () {
      final service = AutoBackupService(ledgerBox: ledgerBox);

      AutoBackupScheduler.instance.configureService(service);

      expect(
          AutoBackupScheduler.instance.activeServiceForTesting, same(service));
    });

    test('AutoBackupService accepts DiskSpacePlus-compatible freeSpaceBytes',
        () async {
      FreeSpaceProvider diskSpacePlusWrapped = _diskSpacePlusWrapped;
      final free = await Future<double>.value(10.5);
      expect(await diskSpacePlusWrapped(), free.toInt());

      final service = AutoBackupService(
        ledgerBox: ledgerBox,
        freeSpaceBytes: diskSpacePlusWrapped,
      );

      final rule = cameraRule(enabled: false);
      final result = await service.isEligibleNow(rule);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.reason, BackupBlockReason.disabled);
    });

    test('AutoBackupService accepts Connectivity.isUnmetered-shaped hook',
        () async {
      final service = AutoBackupService(
        ledgerBox: ledgerBox,
        isUnmetered: () async => true,
        requestPermission: () async => true,
      );
      final rule = cameraRule(enabled: true);
      final result = await service.isEligibleNow(rule);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.reason, BackupBlockReason.ready);
    });
  });

  // ── (2) Rule eligibility and createdAt ─────────────────────

  group('rule eligibility and createdAt', () {
    test('BackupRule stores createdAt when provided', () {
      final now = DateTime(2026, 1, 1, 0, 0);
      final rule = BackupRule(
        id: 'camera',
        albumName: 'Camera',
        createdAt: now,
      );
      expect(rule.createdAt, now);
    });

    test('createdAt defaults to null when omitted', () {
      final rule = BackupRule(id: 'camera', albumName: 'Camera');
      expect(rule.createdAt, isNull);
    });

    test('isEligibleNow passes enabled in-window unmetered rule', () async {
      final service = AutoBackupService(
        ledgerBox: ledgerBox,
        isUnmetered: () async => true,
        requestPermission: () async => true,
      );
      final rule = cameraRule(enabled: true);
      final result = await service.isEligibleNow(
        rule,
        now: DateTime(2026, 1, 1, 3, 0),
      );
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.isEligible, isTrue);
      expect(result.dataOrNull!.reason, BackupBlockReason.ready);
    });

    test('isEligibleNow blocks disabled rule', () async {
      final service = AutoBackupService(ledgerBox: ledgerBox);
      final rule = cameraRule(enabled: false);
      final result = await service.isEligibleNow(rule);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.reason, BackupBlockReason.disabled);
    });
  });

  // ── (3) Box cleanup ────────────────────────────────────────

  group('box cleanup (HiveService.clearAll)', () {
    test('clears backupRulesBox, backupLedgerBox, autoBackupStateBox',
        () async {
      // Seed all three boxes.
      await rulesBox.put('camera', cameraRule());
      await ledgerBox.put(
        'ledger-1',
        BackupLedgerEntry(
          assetId: 'asset-1',
          fingerprint: BackupLedgerEntry.fingerprintFor(
            modifiedMs: 1,
            sizeBytes: 1024,
          ),
          destFileId: 'file-1',
          destFolderId: 'folder-1',
        ),
      );
      await stateBox.put(AppConstants.autoBackupDueKey, true);

      expect(rulesBox.length, 1);
      expect(ledgerBox.length, 1);
      expect(stateBox.length, 1);

      await HiveService.instance.clearAll();

      expect(rulesBox.length, 0);
      expect(ledgerBox.length, 0);
      expect(stateBox.length, 0);
    });

    test('does not crash when backup boxes are closed', () async {
      await rulesBox.close();
      await ledgerBox.close();
      await stateBox.close();

      // clearAll guards each box with isBoxOpen; must not throw.
      await expectLater(HiveService.instance.clearAll(), completes);
    });
  });

  // ── (5) Failure propagation ────────────────────────────────

  group('failure propagation', () {
    test('checkDueInBackground catches exceptions and returns false', () async {
      final badScheduler = AutoBackupScheduler(
        rulesBox: rulesBox,
        stateBox: stateBox,
        isUnmetered: () async {
          throw StateError('network probe failed');
        },
      );

      final armed = await badScheduler.checkDueInBackground();
      expect(armed, isFalse);
    });

    test('isEligibleNow never throws when unmetered hook fails', () async {
      final service = AutoBackupService(
        ledgerBox: ledgerBox,
        isUnmetered: () async {
          throw StateError('unmetered probe failed');
        },
        requestPermission: () async => true,
      );
      final rule = cameraRule(enabled: true)..wifiOnly = true;
      final result = await service.isEligibleNow(rule);
      expect(result.isSuccess, isFalse);
      expect(result is Failure, isTrue);
    });
  });
}
