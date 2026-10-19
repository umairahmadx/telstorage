/*
 * File: auto_backup_scheduler.dart
 * Description: Foreground auto-backup scheduler bridging the Workmanager
 * due-flag to the UploadBloc pipeline. The background due-check is Hive-only
 * (isolate-safe); uploads always run in the main isolate.
 */

import 'package:hive/hive.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:workmanager/workmanager.dart';

import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/services/auto_backup_service.dart';
import 'package:telstorage/core/services/auto_backup_types.dart';
import 'package:telstorage/core/services/notification_service.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';
import 'package:telstorage/core/utils/app_logger.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_view_model.dart';
import 'package:telstorage/shared/widgets/device_file_picker/device_media_scanner.dart';

/// Schedules and runs camera-album auto-backup runs.
///
/// The background due-check ([checkDueInBackground]) is Hive-only so it is
/// safe inside the Workmanager isolate: it never touches Telegram,
/// photo_manager, or the UploadBloc. Real uploads always run in the main
/// isolate via [consumeDueFlag], which is also invoked on app start/resume
/// and the manual "Back up now" button. See plan Task 4 (edge cases A9, A10,
/// C6, C2, F1, F3, A12).
class AutoBackupScheduler {
  /// Workmanager unique name for the 15-minute periodic due-check.
  static const String periodicTaskName = 'telstorage.autoBackupCheck';

  /// Deterministic id prefix for backup upload tasks (A10).
  static const String taskIdPrefix = 'backup:';

  /// Production singleton wired in ServiceLocator.
  static final AutoBackupScheduler instance = AutoBackupScheduler();

  final AutoBackupService _service;
  final Box<BackupRule>? _rulesBox;
  final Box<bool>? _stateBox;
  UploadBloc? _bloc;
  final BackupScheduleAction _registerTask;
  final BackupScheduleAction _cancelTask;
  final BackupPathResolver _resolvePath;
  final BackupNotifier _notify;
  final UnmeteredProvider _isUnmetered;
  final Duration _pollInterval;
  final Duration _watchTimeout;

  /// Constructs AutoBackupScheduler with injectable seams for tests.
  AutoBackupScheduler({
    AutoBackupService? service,
    Box<BackupRule>? rulesBox,
    Box<bool>? stateBox,
    UploadBloc? uploadBloc,
    BackupScheduleAction? registerTask,
    BackupScheduleAction? cancelTask,
    BackupPathResolver? resolvePath,
    BackupNotifier? notify,
    UnmeteredProvider? isUnmetered,
    Duration pollInterval = const Duration(seconds: 2),
    Duration watchTimeout = const Duration(minutes: 30),
  })  : _service = service ?? AutoBackupService(),
        _rulesBox = rulesBox,
        _stateBox = stateBox,
        _bloc = uploadBloc,
        _registerTask = registerTask ?? _defaultRegister,
        _cancelTask = cancelTask ?? _defaultCancel,
        _resolvePath = resolvePath ?? _defaultResolve,
        _notify = notify ?? _defaultNotify,
        _isUnmetered = isUnmetered ?? Connectivity.isUnmetered,
        _pollInterval = pollInterval,
        _watchTimeout = watchTimeout;

  /// Resolves the rules box (opened in main.dart).
  Box<BackupRule> get _rules =>
      _rulesBox ?? Hive.box<BackupRule>(AppConstants.backupRulesBox);

  /// Resolves the scheduler state box (opened in main.dart).
  Box<bool> get _state =>
      _stateBox ?? Hive.box<bool>(AppConstants.autoBackupStateBox);

  /// Attaches the UploadBloc pipeline (the bloc lives in the widget tree).
  void attachUploadBloc(UploadBloc bloc) => _bloc = bloc;

  /// Whether an UploadBloc pipeline is attached.
  bool get hasUploadBloc => _bloc != null;
  /// Registers the 15-minute Workmanager periodic due-check.
  Future<void> registerPeriodic() async {
    await _registerTask(periodicTaskName);
  }

  /// Cancels the periodic task and clears the due flag (A12 logout teardown).
  Future<void> teardown() async {
    await _cancelTask(periodicTaskName);
    try {
      if (_state.isOpen) await _state.put(AppConstants.autoBackupDueKey, false);
    } catch (_) {}
  }

  /// Isolate-safe due-check: Hive-only, never touches Telegram/photo_manager.
  ///
  /// Arms the due flag when any enabled rule is inside its window and (for
  /// wifiOnly rules) on an unmetered network. Permission is intentionally
  /// NOT checked here (F2) — the foreground run gates on it. Returns whether
  /// the flag was armed. Never clears an already-armed flag, so a closing
  /// window cannot drop a pending backup.
  Future<bool> checkDueInBackground({DateTime? now}) async {
    try {
      final at = now ?? DateTime.now();
      for (final rule in _rules.values) {
        if (!rule.enabled) continue;
        if (!rule.isInWindow(at)) continue;
        if (rule.wifiOnly && !await _isUnmetered()) continue;
        await _state.put(AppConstants.autoBackupDueKey, true);
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.w('Backup due-check failed: $e', tag: 'AutoBackupScheduler');
      return false;
    }
  }

  /// Foreground run: consume the due flag, enqueue, watermark completions.
  ///
  /// Also the "Back up now" entry point ([manual]) and the app
  /// start/resume hook (killed-app recovery, C2). The due flag is consumed
  /// only after the rule passes eligibility, so an ineligible run (window,
  /// metered, not charging, permission) never loses the flag — it stays
  /// armed and is retried when conditions change. Uploads never run in the
  /// Workmanager isolate — this must be called on the main isolate only.
  Future<BackupRunOutcome> consumeDueFlag({bool manual = false}) async {
    final due = _state.get(AppConstants.autoBackupDueKey, defaultValue: false) ??
        false;
    if (!due && !manual) {
      return const BackupRunOutcome(
        status: BackupRunStatus.notDue,
        label: 'Not due',
      );
    }

    final rule = _firstEnabledRule();
    if (rule == null) {
      return const BackupRunOutcome(
        status: BackupRunStatus.noRule,
        label: 'Off',
      );
    }

    final eligibility = await _service.isEligibleNow(rule);
    if (eligibility.isFailure) {
      return BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: eligibility.failureOrNull?.message ?? 'Eligibility failed',
      );
    }
    final verdict = eligibility.dataOrNull!;
    if (!verdict.isEligible) {
      return BackupRunOutcome(
        status: BackupRunStatus.ineligible,
        label: verdict.label,
      );
    }

    // Consume the due flag only when the rule is eligible and we are about
    // to attempt a backup. Ineligible runs leave the flag armed for retry.
    await _state.put(AppConstants.autoBackupDueKey, false);

    final collected = await _service.collectDueAssets(rule);
    if (collected.isFailure) {
      return BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: collected.failureOrNull?.message ?? 'Scan failed',
      );
    }
    final result = collected.dataOrNull!;
    final uploads = result.uploads;
    if (uploads.isEmpty) {
      return BackupRunOutcome(
        status: BackupRunStatus.ran,
        label: 'Already up to date',
        skippedUnresolvable: result.skippedUnresolvable,
      );
    }

    final pathResult = await _service.ensureBackupPath(
      rule.albumName,
      rule: rule,
    );
    if (pathResult.isFailure) {
      return BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: pathResult.failureOrNull?.message ?? 'Path setup failed',
      );
    }
    final albumFolderId = pathResult.dataOrNull!.albumFolderId;

    final freeSpace = await _service.ensureFreeSpaceFor(
      uploads.map((u) => u.asset).toList(),
    );
    if (freeSpace.isFailure) {
      return BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: freeSpace.failureOrNull?.message ?? 'Low storage',
      );
    }

    final planned = <String, BackupUploadItem>{};
    final tasks = <UploadTask>[];
    for (final upload in uploads) {
      final asset = upload.asset;
      final taskId = '$taskIdPrefix${asset.assetId}:${asset.fingerprint}';
      if (_isActive(taskId)) continue;
      final resolved = await _resolvePath(asset);
      if (resolved == null) continue;
      tasks.add(UploadTask(
        id: taskId,
        path: resolved.path,
        name: upload.destinationName,
        size: asset.sizeBytes,
        folderId: albumFolderId,
        isTemporaryCacheFile: resolved.isTemporary,
      ));
      planned[taskId] = upload;
    }
    if (tasks.isEmpty) {
      return BackupRunOutcome(
        status: BackupRunStatus.ran,
        label: 'Already up to date',
        skippedUnresolvable: result.skippedUnresolvable,
      );
    }

    return _enqueueAndWatch(
      rule: rule,
      tasks: tasks,
      planned: planned,
      albumFolderId: albumFolderId,
      skippedUnresolvable: result.skippedUnresolvable,
    );
  }

  /// Enqueues tasks and polls until all reach a terminal state.
  ///
  /// Advances the watermark only for tasks that reach [TransferStatus]
  /// .completed (A9); failures and mid-run cancellations (C6) never write a
  /// ledger row. A rule disabled mid-run cancels still-queued tasks.
  Future<BackupRunOutcome> _enqueueAndWatch({
    required BackupRule rule,
    required List<UploadTask> tasks,
    required Map<String, BackupUploadItem> planned,
    required String albumFolderId,
    required int skippedUnresolvable,
  }) async {
    final bloc = _bloc;
    if (bloc == null) {
      return const BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: 'Upload pipeline unavailable',
      );
    }
    bloc.add(AddUploads(tasks));

    final pending = planned.keys.toSet();
    final completedIds = <String>[];
    final deadline = DateTime.now().add(_watchTimeout);

    while (pending.isNotEmpty && DateTime.now().isBefore(deadline)) {
      if (!rule.enabled) {
        for (final id in pending) {
          bloc.add(CancelUploadTask(id));
        }
        pending.clear();
        break;
      }
      for (final id in pending.toList()) {
        final task = _findTask(id);
        if (task == null) continue;
        if (task.status == TransferStatus.completed) {
          completedIds.add(id);
          pending.remove(id);
        } else if (task.status == TransferStatus.failed ||
            task.status == TransferStatus.cancelled) {
          pending.remove(id);
        }
      }
      if (pending.isNotEmpty) {
        await Future<void>.delayed(_pollInterval);
      }
    }

    var photos = 0;
    var videos = 0;
    if (completedIds.isNotEmpty) {
      final destIds = <String, String>{
        for (final id in completedIds) planned[id]!.asset.assetId: id,
      };
      final completedUploads = completedIds.map((id) => planned[id]!).toList();
      await _service.advanceWatermark(
        rule: rule,
        uploads: completedUploads,
        destFileIdsByAssetId: destIds,
        destFolderId: albumFolderId,
      );
      for (final upload in completedUploads) {
        if (upload.asset.isVideo) {
          videos++;
        } else {
          photos++;
        }
      }
    }

    await _service.enforceRetention(rule);

    if (photos + videos > 0) {
      await _notify(
        'Backup complete',
        'Backed up $photos photos, $videos videos',
      );
    }

    return BackupRunOutcome(
      status: BackupRunStatus.ran,
      label: 'Backed up $photos photos, $videos videos',
      uploadedPhotos: photos,
      uploadedVideos: videos,
      skippedUnresolvable: skippedUnresolvable,
    );
  }

  /// First enabled rule, or null when none is enabled.
  BackupRule? _firstEnabledRule() {
    for (final rule in _rules.values) {
      if (rule.enabled) return rule;
    }
    return null;
  }

  /// Whether an active (non-terminal) transfer already covers [taskId] (A10).
  bool _isActive(String taskId) {
    for (final task in TransferQueueService.instance.activeTasks) {
      if (task.id == taskId) return true;
    }
    return false;
  }

  /// Looks up a task in the transfer queue by id.
  TransferTask? _findTask(String taskId) {
    for (final task in TransferQueueService.instance.tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  /// Default Workmanager registration (15-minute cadence).
  static Future<void> _defaultRegister(String uniqueName) =>
      Workmanager().registerPeriodicTask(
        uniqueName,
        uniqueName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );

  /// Default Workmanager cancellation.
  static Future<void> _defaultCancel(String uniqueName) =>
      Workmanager().cancelByUniqueName(uniqueName);

  /// Default path resolver: re-fetch the AssetEntity by id and resolve via
  /// DeviceMediaScanner. Runs on the main isolate only (Android zero-copy
  /// path, iOS temp fallback, F3). Returns null when unreachable so the run
  /// skips it without blocking other assets.
  static Future<({String path, bool isTemporary})?> _defaultResolve(
    BackupAsset asset,
  ) async {
    try {
      final entity = await AssetEntity.fromId(asset.assetId);
      if (entity == null) return null;
      final resolved = await DeviceMediaScanner.resolveUploadPath(entity);
      return (path: resolved.$1, isTemporary: resolved.$2);
    } catch (e) {
      AppLogger.w('Backup path resolve failed ${asset.assetId}: $e',
          tag: 'AutoBackupScheduler');
      return null;
    }
  }

  /// Default summary notifier via the app NotificationService.
  static Future<void> _defaultNotify(String title, String body) async {
    await NotificationService.instance.showCompletionNotification(
      title: title,
      body: body,
      payload: 'auto_backup',
    );
  }
}

