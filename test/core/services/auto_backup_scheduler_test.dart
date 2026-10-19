/*
 * File: auto_backup_scheduler_test.dart
 * Description: Unit tests for AutoBackupScheduler due-flag gating,
 * deterministic enqueue, completion watermarking, and logout teardown.
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/services/auto_backup_scheduler.dart';
import 'package:telstorage/core/services/auto_backup_service.dart';
import 'package:telstorage/core/services/auto_backup_types.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_view_model.dart';

/// Records AddUploads enqueues without driving the real upload queue.
class _RecordingUploadBloc extends UploadBloc {
  /// Every UploadTask passed to AddUploads, in order.
  final List<UploadTask> enqueued = [];

  /// Task ids passed to CancelUploadTask (C6).
  final List<String> cancelled = [];

  /// Status stamped on tasks as they are enqueued.
  TransferStatus enqueueStatus = TransferStatus.completed;

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
          status: enqueueStatus,
        ));
      }
      return;
    }
    if (event is CancelUploadTask) {
      cancelled.add(event.taskId);
      TransferQueueService.instance.cancelTask(event.taskId);
      return;
    }
    // Swallow every other event — never run real uploads in tests.
  }
}

/// Fake service returning canned eligibility/plan and recording side effects.
class _FakeBackupService extends AutoBackupService {
  /// Verdict returned by isEligibleNow.
  BackupEligibility eligibility;

  /// Plan returned by collectDueAssets.
  BackupPlan plan;

  /// destFileIdsByAssetId map of every advanceWatermark call, in order.
  final List<Map<String, String>> watermarkCalls = [];

  /// Count of enforceRetention invocations.
  int retentionCalls = 0;

  /// Constructs _FakeBackupService.
  _FakeBackupService({
    required this.eligibility,
    required this.plan,
    required Box<BackupLedgerEntry> ledgerBox,
  }) : super(ledgerBox: ledgerBox);

  @override
  Future<Result<BackupEligibility>> isEligibleNow(
    BackupRule rule, {
    DateTime? now,
  }) async =>
      Success(eligibility);

  @override
  Future<Result<BackupCollectResult>> collectDueAssets(
    BackupRule rule, {
    int maxItems = AutoBackupService.defaultMaxItems,
    int maxBytes = AutoBackupService.defaultMaxBytes,
  }) async =>
      Success(BackupCollectResult(plan: plan));

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
    watermarkCalls.add(destFileIdsByAssetId);
    return const Success(null);
  }

  @override
  Future<Result<int>> enforceRetention(BackupRule rule) async {
    retentionCalls++;
    return const Success(0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<BackupRule> rulesBox;
  late Box<BackupLedgerEntry> ledgerBox;
  late Box<bool> stateBox;
  late _RecordingUploadBloc bloc;
  late _FakeBackupService fakeService;

  final registeredTasks = <String>[];
  final cancelledTasks = <String>[];
  final notifications = <String>[];

  BackupRule cameraRule({
    bool enabled = true,
    int windowStart = 0,
    int windowEnd = 1440,
  }) =>
      BackupRule(
        id: 'camera',
        albumName: 'Camera',
        enabled: enabled,
        backfillDone: true,
        createdAt: DateTime(2025, 6, 1),
        windowStartMinutes: windowStart,
        windowEndMinutes: windowEnd,
      );

  BackupAsset asset(String id, String title, {bool isVideo = false}) =>
      BackupAsset(
        assetId: id,
        title: title,
        modifiedMs: 1749000000000,
        sizeBytes: 2048,
        isVideo: isVideo,
      );

  String taskIdFor(BackupAsset a) => 'backup:${a.assetId}:${a.fingerprint}';

  AutoBackupScheduler buildScheduler({
    Future<({String path, bool isTemporary})?> Function(BackupAsset asset)?
        resolvePath,
    bool temporaryPaths = false,
    Duration pollInterval = const Duration(milliseconds: 10),
    Duration watchTimeout = const Duration(seconds: 2),
  }) =>
      AutoBackupScheduler(
        service: fakeService,
        rulesBox: rulesBox,
        stateBox: stateBox,
        uploadBloc: bloc,
        registerTask: (name) async => registeredTasks.add(name),
        cancelTask: (name) async => cancelledTasks.add(name),
        resolvePath: resolvePath ??
            ((a) async =>
                (path: '/fake/${a.title}', isTemporary: temporaryPaths)),
        notify: (title, body) async => notifications.add('$title|$body'),
        isUnmetered: () async => true,
        pollInterval: pollInterval,
        watchTimeout: watchTimeout,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_sched_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FileRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(FolderRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(BackupRuleAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(BackupLedgerEntryAdapter());
    }
    await Hive.openBox<FileRecord>(AppConstants.filesBox);
    await Hive.openBox<FolderRecord>(AppConstants.foldersBox);
    rulesBox = await Hive.openBox<BackupRule>(AppConstants.backupRulesBox);
    ledgerBox = await Hive.openBox<BackupLedgerEntry>(
      AppConstants.backupLedgerBox,
    );
    stateBox = await Hive.openBox<bool>(AppConstants.autoBackupStateBox);
    await rulesBox.clear();
    await ledgerBox.clear();
    await stateBox.clear();

    TransferQueueService.instance.clearAll();
    registeredTasks.clear();
    cancelledTasks.clear();
    notifications.clear();

    bloc = _RecordingUploadBloc();
    fakeService = _FakeBackupService(
      eligibility: const BackupEligibility(BackupBlockReason.ready),
      plan: const BackupPlan(uploads: [], adoptions: []),
      ledgerBox: ledgerBox,
    );
  });

  tearDown(() async {
    TransferQueueService.instance.clearAll();
    await bloc.close();
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('checkDueInBackground', () {
    test('sets the due flag only when the rule is eligible', () async {
      await rulesBox.put('camera', cameraRule());
      final scheduler = buildScheduler();

      final due = await scheduler.checkDueInBackground(
        now: DateTime(2026, 1, 1, 3, 0),
      );

      expect(due, isTrue);
      expect(stateBox.get(AppConstants.autoBackupDueKey), isTrue);
    });

    test('disabled or outside-window rules never arm the flag', () async {
      final scheduler = buildScheduler();

      await rulesBox.put('camera', cameraRule(enabled: false));
      expect(
        await scheduler.checkDueInBackground(
          now: DateTime(2026, 1, 1, 3, 0),
        ),
        isFalse,
      );
      expect(stateBox.get(AppConstants.autoBackupDueKey), isNot(isTrue));

      await rulesBox.put(
        'camera',
        cameraRule(windowStart: 120, windowEnd: 300),
      );
      expect(
        await scheduler.checkDueInBackground(
          now: DateTime(2026, 1, 1, 12, 0),
        ),
        isFalse,
      );
      expect(stateBox.get(AppConstants.autoBackupDueKey), isNot(isTrue));
    });
  });

  group('consumeDueFlag', () {
    test('enqueues exactly 2 UploadTasks with deterministic ids', () async {
      final photo = asset('a1', 'IMG_001.jpg');
      final video = asset('a2', 'VID_001.mp4', isVideo: true);
      fakeService.plan = BackupPlan(
        uploads: [
          BackupUploadItem(asset: photo, destinationName: 'IMG_001.jpg'),
          BackupUploadItem(asset: video, destinationName: 'VID_001.mp4'),
        ],
        adoptions: const [],
      );
      await rulesBox.put('camera', cameraRule());
      await stateBox.put(AppConstants.autoBackupDueKey, true);

      final scheduler = buildScheduler();
      final outcome = await scheduler.consumeDueFlag();

      expect(outcome.status, BackupRunStatus.ran);
      expect(bloc.enqueued, hasLength(2));
      expect(bloc.enqueued.map((t) => t.id),
          [taskIdFor(photo), taskIdFor(video)]);
      expect(bloc.enqueued.every((t) => t.folderId == 'album-1'), isTrue);
      expect(fakeService.watermarkCalls, hasLength(1));
      expect(fakeService.watermarkCalls.single, {
        photo.assetId: taskIdFor(photo),
        video.assetId: taskIdFor(video),
      });
      expect(fakeService.retentionCalls, 1);
      expect(stateBox.get(AppConstants.autoBackupDueKey), isFalse);
      expect(notifications, hasLength(1));
      expect(notifications.single, contains('1 photos, 1 videos'));
    });

    test('no due flag and not manual → nothing enqueued', () async {
      await rulesBox.put('camera', cameraRule());
      final scheduler = buildScheduler();

      final outcome = await scheduler.consumeDueFlag();

      expect(outcome.status, BackupRunStatus.notDue);
      expect(bloc.enqueued, isEmpty);
      expect(fakeService.watermarkCalls, isEmpty);
    });

    test('manual run bypasses the due flag (Back up now)', () async {
      final photo = asset('m1', 'IMG_MANUAL.jpg');
      fakeService.plan = BackupPlan(
        uploads: [
          BackupUploadItem(asset: photo, destinationName: 'IMG_MANUAL.jpg'),
        ],
        adoptions: const [],
      );
      await rulesBox.put('camera', cameraRule());
      final scheduler = buildScheduler();

      final outcome = await scheduler.consumeDueFlag(manual: true);

      expect(outcome.status, BackupRunStatus.ran);
      expect(bloc.enqueued, hasLength(1));
      expect(bloc.enqueued.single.id, taskIdFor(photo));
    });

    test('ineligible verdict (F1 charging) enqueues nothing', () async {
      await rulesBox.put('camera', cameraRule());
      await stateBox.put(AppConstants.autoBackupDueKey, true);
      fakeService.eligibility =
          const BackupEligibility(BackupBlockReason.notCharging);
      final scheduler = buildScheduler();

      final outcome = await scheduler.consumeDueFlag();

      expect(outcome.status, BackupRunStatus.ineligible);
      expect(outcome.label, 'Waiting for charger');
      expect(bloc.enqueued, isEmpty);
      // Flag stays armed on ineligible runs — retried when conditions change.
      expect(stateBox.get(AppConstants.autoBackupDueKey), isTrue);
    });

    test('iOS temp paths create temporary UploadTasks (F3)', () async {
      final photo = asset('t1', 'IMG_IOS.jpg');
      fakeService.plan = BackupPlan(
        uploads: [
          BackupUploadItem(asset: photo, destinationName: 'IMG_IOS.jpg'),
        ],
        adoptions: const [],
      );
      await rulesBox.put('camera', cameraRule());
      await stateBox.put(AppConstants.autoBackupDueKey, true);
      final scheduler = buildScheduler(temporaryPaths: true);

      final outcome = await scheduler.consumeDueFlag();

      expect(outcome.status, BackupRunStatus.ran);
      expect(bloc.enqueued.single.isTemporaryCacheFile, isTrue);
    });

    test('active same-id task is deduped (A10)', () async {
      final photo = asset('d1', 'IMG_DUP.jpg');
      final other = asset('d2', 'IMG_OTHER.jpg');
      fakeService.plan = BackupPlan(
        uploads: [
          BackupUploadItem(asset: photo, destinationName: 'IMG_DUP.jpg'),
          BackupUploadItem(asset: other, destinationName: 'IMG_OTHER.jpg'),
        ],
        adoptions: const [],
      );
      await rulesBox.put('camera', cameraRule());
      await stateBox.put(AppConstants.autoBackupDueKey, true);
      TransferQueueService.instance.addTask(TransferTask(
        id: taskIdFor(photo),
        name: 'IMG_DUP.jpg',
        type: TransferType.upload,
        sizeMb: 0.01,
        addedAt: DateTime.now(),
        status: TransferStatus.uploading,
      ));
      final scheduler = buildScheduler();

      final outcome = await scheduler.consumeDueFlag();

      expect(outcome.status, BackupRunStatus.ran);
      expect(bloc.enqueued.map((t) => t.id), [taskIdFor(other)]);
      expect(
        fakeService.watermarkCalls.single.keys.toList(),
        [other.assetId],
      );
    });

    test('failed upload is never watermarked (A9)', () async {
      final ok = asset('f1', 'IMG_OK.jpg');
      final bad = asset('f2', 'IMG_BAD.jpg');
      fakeService.plan = BackupPlan(
        uploads: [
          BackupUploadItem(asset: ok, destinationName: 'IMG_OK.jpg'),
          BackupUploadItem(asset: bad, destinationName: 'IMG_BAD.jpg'),
        ],
        adoptions: const [],
      );
      await rulesBox.put('camera', cameraRule());
      await stateBox.put(AppConstants.autoBackupDueKey, true);
      final scheduler = buildScheduler();
      bloc.enqueueStatus = TransferStatus.waiting;

      final consuming = scheduler.consumeDueFlag();
      // Wait for both tasks to be enqueued before updating them — a fixed
      // delay is racy under full-suite load (tasks may not exist yet).
      final okId = taskIdFor(ok);
      final badId = taskIdFor(bad);
      while (TransferQueueService.instance.tasks
              .where((t) => t.id == okId || t.id == badId)
              .length <
          2) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      TransferQueueService.instance
          .updateTask(okId, status: TransferStatus.completed);
      TransferQueueService.instance
          .updateTask(badId, status: TransferStatus.failed);
      final outcome = await consuming;

      expect(outcome.status, BackupRunStatus.ran);
      expect(outcome.uploadedPhotos, 1);
      expect(fakeService.watermarkCalls.single.keys.toList(), [ok.assetId]);
    });

    test('disabling mid-run cancels queued tasks (C6)', () async {
      final photo = asset('c1', 'IMG_CANCEL.jpg');
      fakeService.plan = BackupPlan(
        uploads: [
          BackupUploadItem(asset: photo, destinationName: 'IMG_CANCEL.jpg'),
        ],
        adoptions: const [],
      );
      final rule = cameraRule();
      await rulesBox.put('camera', rule);
      await stateBox.put(AppConstants.autoBackupDueKey, true);
      final scheduler = buildScheduler();
      bloc.enqueueStatus = TransferStatus.waiting;

      final consuming = scheduler.consumeDueFlag();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      rule.enabled = false;
      final outcome = await consuming;

      expect(bloc.cancelled, [taskIdFor(photo)]);
      expect(fakeService.watermarkCalls, isEmpty);
      expect(fakeService.retentionCalls, 1);
      expect(stateBox.get(AppConstants.autoBackupDueKey), isFalse);
      expect(outcome.status, BackupRunStatus.ran);
    });
  });

  group('register and teardown', () {
    test('registerPeriodic registers the 15-minute task', () async {
      final scheduler = buildScheduler();
      await scheduler.registerPeriodic();
      expect(registeredTasks, [AutoBackupScheduler.periodicTaskName]);
    });

    test('teardown cancels periodic task and clears flag (A12)', () async {
      await rulesBox.put('camera', cameraRule());
      final scheduler = buildScheduler();
      await scheduler.checkDueInBackground(
        now: DateTime(2026, 1, 1, 3, 0),
      );
      expect(stateBox.get(AppConstants.autoBackupDueKey), isTrue);

      await scheduler.teardown();

      expect(cancelledTasks, [AutoBackupScheduler.periodicTaskName]);
      expect(stateBox.get(AppConstants.autoBackupDueKey), isFalse);
    });
  });
}

