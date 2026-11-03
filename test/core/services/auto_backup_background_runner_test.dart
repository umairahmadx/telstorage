/*
 * File: auto_backup_background_runner_test.dart
 * Description: Deterministic coverage for the Android background backup pass.
 */

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/services/auto_backup_background_runner.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/services/auto_backup_service.dart';
import 'package:telstorage/core/services/auto_backup_types.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/upload_service.dart';

class _FakeBackupService extends AutoBackupService {
  final BackupUploadItem upload;
  bool failWatermark = false;
  int watermarkCalls = 0;

  _FakeBackupService(Box<BackupLedgerEntry> ledgerBox, this.upload)
      : super(
          ledgerBox: ledgerBox,
          requestPermission: () async => true,
          hasPermission: () async => true,
          isUnmetered: () async => true,
          freeSpaceBytes: () async => 1024 * 1024 * 1024,
        );

  @override
  Future<Result<BackupEligibility>> isEligibleNow(
    BackupRule rule, {
    DateTime? now,
  }) async =>
      const Success(BackupEligibility(BackupBlockReason.ready));

  @override
  Future<Result<BackupCollectResult>> collectDueAssets(
    BackupRule rule, {
    int maxItems = AutoBackupService.defaultMaxItems,
    int maxBytes = AutoBackupService.defaultMaxBytes,
    bool includeBackfill = false,
  }) async {
    return Success(
      BackupCollectResult(
        plan: BackupPlan(uploads: [upload], adoptions: const []),
      ),
    );
  }

  @override
  Future<Result<BackupPath>> ensureBackupPath(
    String albumName, {
    BackupRule? rule,
  }) async =>
      const Success(
        BackupPath(backupFolderId: 'backup-root', albumFolderId: 'album-1'),
      );

  @override
  Future<Result<void>> ensureFreeSpaceFor(List<BackupAsset> assets) async =>
      const Success(null);

  @override
  Future<Result<void>> advanceWatermark({
    required BackupRule rule,
    required List<BackupUploadItem> uploads,
    required Map<String, String> destFileIdsByAssetId,
    String? destFolderId,
    bool deleteReplaced = true,
  }) async {
    watermarkCalls++;
    if (failWatermark) {
      return const Failure(UnknownFailure('watermark failed'));
    }
    return super.advanceWatermark(
      rule: rule,
      uploads: uploads,
      destFileIdsByAssetId: destFileIdsByAssetId,
      destFolderId: destFolderId,
      deleteReplaced: deleteReplaced,
    );
  }

  @override
  Future<Result<int>> enforceRetention(BackupRule rule) async =>
      const Success(0);
}

class _FakeUploadService extends UploadService {
  _FakeUploadService()
      : super(TelegramService(), MetadataService(TelegramService()),
            HiveService.instance);

  bool failUpload = false;
  bool failCommit = false;
  int commitCalls = 0;

  @override
  Future<Result<Map<String, dynamic>>> uploadFile(
    Uint8List? bytes,
    String name,
    String? folderId,
    void Function(double progress, String status) onProgress, {
    String? filePath,
    int? fileLength,
    bool skipGlobalMetadataUpdate = false,
    String? taskId,
    String? precomputedHash,
    Uint8List? precomputedThumbnailBytes,
    String? thumbnailExtension,
  }) async {
    if (failUpload) return const Failure(UnknownFailure('upload failed'));
    return const Success({'metadata_file_id': 'cloud-file-1'});
  }

  @override
  Future<void> commitUploadBatch(
      List<Map<String, dynamic>> filesDataList) async {
    commitCalls++;
    if (failCommit) throw StateError('metadata commit failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<BackupRule> rulesBox;
  late Box<BackupLedgerEntry> ledgerBox;
  late Box<bool> stateBox;

  const asset = BackupAsset(
    assetId: 'asset-1',
    title: 'IMG_0001.jpg',
    modifiedMs: 1749000000000,
    sizeBytes: 2048,
    isVideo: false,
  );
  const upload = BackupUploadItem(
    asset: asset,
    destinationName: 'IMG_0001.jpg',
  );

  BackupRule rule() => BackupRule(
        id: 'camera',
        albumName: 'Camera',
        enabled: true,
        backfillDone: true,
        windowStartMinutes: 0,
        windowEndMinutes: 1440,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_runner_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(BackupRuleAdapter());
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(BackupLedgerEntryAdapter());
    }
    rulesBox = await Hive.openBox<BackupRule>(AppConstants.backupRulesBox);
    ledgerBox = await Hive.openBox<BackupLedgerEntry>(
      AppConstants.backupLedgerBox,
    );
    stateBox = await Hive.openBox<bool>(AppConstants.autoBackupStateBox);
    await rulesBox.clear();
    await ledgerBox.clear();
    await stateBox.clear();
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  AutoBackupBackgroundRunner runner(
    _FakeBackupService backup,
    _FakeUploadService uploads, {
    Future<({String path, bool isTemporary})?> Function(BackupAsset)? resolve,
  }) {
    return AutoBackupBackgroundRunner(
      backup: backup,
      uploads: uploads,
      rules: rulesBox,
      state: stateBox,
      resolvePath: resolve ??
          (asset) async => (path: '/fake/${asset.title}', isTemporary: false),
    );
  }

  test('credential loading fails closed when background credentials are absent',
      () async {
    final requested = <String>[];
    final outcome = await AutoBackupBackgroundRunner.runProduction(
      readCredential: (key) async {
        requested.add(key);
        return null;
      },
    );

    expect(outcome.status, BackupRunStatus.failed);
    expect(outcome.label, contains('credentials unavailable'));
    expect(requested, contains(AppConstants.keyBotToken));
    expect(requested, contains(AppConstants.keyChannelId));
  });

  test('successful background upload commits metadata and advances the ledger',
      () async {
    await rulesBox.put('camera', rule());
    await stateBox.put(AppConstants.autoBackupDueKey, true);
    final backup = _FakeBackupService(ledgerBox, upload);
    final uploads = _FakeUploadService();

    final outcome = await runner(backup, uploads).run();

    expect(outcome.uploadedPhotos, 1);
    expect(outcome.needsRetry, isFalse);
    expect(stateBox.get(AppConstants.autoBackupDueKey), isFalse);
    expect(uploads.commitCalls, 1);
    expect(backup.watermarkCalls, 1);
    expect(ledgerBox.get(asset.assetId)?.destFileId, 'cloud-file-1');
  });

  test('unresolvable MediaStore paths remain due for a later retry', () async {
    await rulesBox.put('camera', rule());
    await stateBox.put(AppConstants.autoBackupDueKey, true);
    final backup = _FakeBackupService(ledgerBox, upload);
    final uploads = _FakeUploadService();
    var resolverCalls = 0;

    final outcome = await runner(
      backup,
      uploads,
      resolve: (_) async {
        resolverCalls++;
        return null;
      },
    ).run();

    expect(resolverCalls, 1);
    expect(outcome.skippedUnresolvable, 1);
    expect(outcome.needsRetry, isTrue);
    expect(stateBox.get(AppConstants.autoBackupDueKey), isTrue);
    expect(uploads.commitCalls, 0);
  });

  test('upload failure does not advance the ledger or clear the due flag',
      () async {
    await rulesBox.put('camera', rule());
    await stateBox.put(AppConstants.autoBackupDueKey, true);
    final backup = _FakeBackupService(ledgerBox, upload);
    final uploads = _FakeUploadService()..failUpload = true;

    final outcome = await runner(backup, uploads).run();

    expect(outcome.needsRetry, isTrue);
    expect(stateBox.get(AppConstants.autoBackupDueKey), isTrue);
    expect(backup.watermarkCalls, 0);
    expect(ledgerBox.get(asset.assetId), isNull);
  });

  test('metadata commit failure preserves retry state and ledger safety',
      () async {
    await rulesBox.put('camera', rule());
    await stateBox.put(AppConstants.autoBackupDueKey, true);
    final backup = _FakeBackupService(ledgerBox, upload);
    final uploads = _FakeUploadService()..failCommit = true;

    final outcome = await runner(backup, uploads).run();

    expect(outcome.needsRetry, isTrue);
    expect(stateBox.get(AppConstants.autoBackupDueKey), isTrue);
    expect(backup.watermarkCalls, 0);
    expect(ledgerBox.get(asset.assetId), isNull);
  });
}
