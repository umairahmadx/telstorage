/*
 * File: auto_backup_upload_failure_reproduction_test.dart
 * Description: Automated reproduction test verifying folder creation preceding upload,
 * outcome status misclassification on failed upload batches, and colon-containing task IDs.
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/auto_backup_scheduler.dart';
import 'package:telstorage/core/services/auto_backup_service.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/services/auto_backup_types.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_view_model.dart';

class _FailingUploadBloc extends UploadBloc {
  final List<UploadTask> enqueued = [];

  @override
  void add(UploadEvent event) {
    if (event is AddUploads) {
      enqueued.addAll(event.tasks);
      for (final task in event.tasks) {
        TransferQueueService.instance.addTask(TransferTask(
          id: task.id,
          name: task.name,
          type: TransferType.upload,
          sizeMb: (task.size ?? 0) / 1048576,
          addedAt: DateTime.now(),
          status: TransferStatus.failed,
          error: 'Upload failed intentionally',
        ));
      }
    }
  }
}

class _FolderCreatingBackupService extends AutoBackupService {
  final List<String> createdFolders = [];
  final BackupPlan plan;

  _FolderCreatingBackupService({
    required this.plan,
    required super.ledgerBox,
  });

  @override
  Future<Result<BackupEligibility>> isEligibleNowManual(
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
  }) async =>
      Success(BackupCollectResult(plan: plan));

  @override
  Future<Result<BackupPath>> ensureBackupPath(
    String albumName, {
    BackupRule? rule,
  }) async {
    createdFolders.add('root/Backup');
    createdFolders.add('root/Backup/$albumName');
    return const Success(
      BackupPath(backupFolderId: 'backup-root', albumFolderId: 'album-1'),
    );
  }

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
  }) async =>
      const Success(null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<BackupRule> rulesBox;
  late Box<BackupLedgerEntry> ledgerBox;
  late Box<bool> stateBox;
  late _FailingUploadBloc bloc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_upload_fail_repro_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(BackupRuleAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(BackupLedgerEntryAdapter());
    }
    rulesBox = await Hive.openBox<BackupRule>(AppConstants.backupRulesBox);
    ledgerBox =
        await Hive.openBox<BackupLedgerEntry>(AppConstants.backupLedgerBox);
    stateBox = await Hive.openBox<bool>(AppConstants.autoBackupStateBox);

    await rulesBox.clear();
    await ledgerBox.clear();
    await stateBox.clear();
    TransferQueueService.instance.clearAll();

    bloc = _FailingUploadBloc();
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('AutoBackup Upload Failure Reproduction', () {
    test(
        'folders are created but complete upload batch failure must return BackupRunStatus.failed',
        () async {
      final rule = BackupRule(
        id: 'camera',
        albumName: 'Camera',
        enabled: true,
      );
      await rulesBox.put('camera', rule);

      const asset = BackupAsset(
        assetId: 'asset_1',
        title: 'IMG_0001.jpg',
        relativePath: 'DCIM/Camera/',
        modifiedMs: 1700000000000,
        sizeBytes: 2048,
        isVideo: false,
      );

      const plan = BackupPlan(
        uploads: [
          BackupUploadItem(
            asset: asset,
            destinationName: 'IMG_0001.jpg',
          ),
        ],
        adoptions: [],
      );

      final service = _FolderCreatingBackupService(
        plan: plan,
        ledgerBox: ledgerBox,
      );

      final scheduler = AutoBackupScheduler(
        service: service,
        rulesBox: rulesBox,
        stateBox: stateBox,
        uploadBloc: bloc,
        resolvePath: (a) async => (path: '/dummy/path/IMG_0001.jpg', isTemporary: false),
        pollInterval: const Duration(milliseconds: 20),
        watchTimeout: const Duration(seconds: 2),
      );

      final outcome = await scheduler.consumeDueFlag(manual: true);

      // 1. Folders WERE created:
      expect(service.createdFolders, contains('root/Backup/Camera'));

      // 2. But upload failed!
      // In current un-fixed code, auto_backup_scheduler_run.dart line 316 returns:
      // BackupRunOutcome(status: BackupRunStatus.ran, needsRetry: true, ...)
      // even when 0 uploads succeeded and all tasks failed!
      // It MUST return BackupRunStatus.failed when all tasks fail.
      expect(
        outcome.status,
        BackupRunStatus.failed,
        reason:
            'When all upload tasks fail, the outcome status must be BackupRunStatus.failed, not BackupRunStatus.ran',
      );
    });

    test('taskIdPrefix conforms to canonical backup: contract (A10)', () {
      expect(
        AutoBackupScheduler.taskIdPrefix,
        'backup:',
        reason: 'Task ID prefix must follow canonical backup: contract',
      );
    });
  });
}
