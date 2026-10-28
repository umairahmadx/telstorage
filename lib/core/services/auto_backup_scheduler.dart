/*
 * File: auto_backup_scheduler.dart
 * Description: Foreground auto-backup scheduler bridging the Workmanager
 * due-flag to the UploadBloc pipeline. The background due-check is Hive-only
 * (isolate-safe); uploads always run in the main isolate.
 */

import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';
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

part 'auto_backup_scheduler_run.dart';

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
  bool _runInProgress = false;

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

  /// Supplies the fully configured foreground service after account services
  /// are initialized. The Workmanager isolate uses its own Hive-only instance.
  void configureService(AutoBackupService service) {
    // The production singleton is attached before scheduled/manual runs.
    // Test schedulers may continue using their constructor-injected service.
    if (identical(this, instance)) _configuredService = service;
  }

  AutoBackupService? _configuredService;
  AutoBackupService get _activeService => _configuredService ?? _service;

  /// The service currently selected by this scheduler.
  @visibleForTesting
  AutoBackupService get activeServiceForTesting => _activeService;

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
