/*
 * File: auto_backup_scheduler.dart
 * Description: Background scheduler for auto-backup — periodic checks, WorkManager integration, and UploadBloc bridge.
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../constants/app_constants.dart';
import '../models/backup_rule.dart';
import '../services/auto_backup_engine.dart';
import '../services/auto_backup_service.dart';
import '../services/device_hardware_service.dart';
import '../services/notification_service.dart';
import '../services/service_locator.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import '../../features/upload/presentation/viewmodels/upload_view_model.dart';
import 'package:hive/hive.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// WorkManager task name for periodic auto-backup checks.
const String _autoBackupTaskName = 'autoBackupPeriodicCheck';

/// Callback signature for when a backup run completes.
typedef BackupRunCallback = Future<void> Function(BackupRunResult result);

/// Manages periodic auto-backup execution and integrates with the upload pipeline.
class AutoBackupScheduler {
  final AutoBackupService _backupService;
  final DeviceHardwareService _deviceHardware;
  final UploadViewModel? _uploadBloc;

  Timer? _periodicTimer;
  bool _isRunning = false;
  BackupRunCallback? _onRunComplete;

  AutoBackupScheduler({
    required AutoBackupService backupService,
    required DeviceHardwareService deviceHardware,
    UploadViewModel? uploadBloc,
  })  : _backupService = backupService,
        _deviceHardware = deviceHardware,
        _uploadBloc = uploadBloc;

  /// Initializes the scheduler: registers WorkManager task and starts periodic timer.
  Future<void> initialize() async {
    // Register WorkManager periodic task (runs even when app is backgrounded)
    try {
      await Workmanager().registerPeriodicTask(
        _autoBackupTaskName,
        _autoBackupTaskName,
        frequency: const Duration(hours: 6),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresCharging: false, // We check charging in eligibility
        ),
      );
      AppLogger.i('AutoBackupScheduler: WorkManager periodic task registered', tag: 'AutoBackupScheduler');
    } catch (e) {
      AppLogger.w('AutoBackupScheduler: WorkManager registration failed: $e', tag: 'AutoBackupScheduler');
    }

    // Start in-app periodic timer (runs while app is alive)
    _startPeriodicTimer();
  }

  /// Starts the in-app periodic timer for auto-backup checks.
  void _startPeriodicTimer() {
    _periodicTimer?.cancel();
    // Check every 30 minutes while app is running
    _periodicTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (!_isRunning && ServiceLocator.instance.isInitialized) {
        unawaited(_checkAndRun());
      }
    });
  }

  /// Sets a callback to be invoked when a backup run completes.
  void setOnRunComplete(BackupRunCallback callback) {
    _onRunComplete = callback;
  }

  /// Triggers an immediate backup check (e.g., on app start/resume or manual "Back up now").
  Future<void> triggerCheck() async {
    if (_isRunning) {
      AppLogger.d('AutoBackupScheduler: Already running, skipping trigger', tag: 'AutoBackupScheduler');
      return;
    }
    await _checkAndRun();
  }

  /// Core check-and-run logic: evaluates eligibility and runs backup if due.
  Future<void> _checkAndRun() async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      AppLogger.i('AutoBackupScheduler: Starting backup check', tag: 'AutoBackupScheduler');

      // Ensure services are initialized
      if (!ServiceLocator.instance.isInitialized) {
        AppLogger.d('AutoBackupScheduler: Services not initialized, skipping', tag: 'AutoBackupScheduler');
        return;
      }

      // Get the camera rule
      final rulesBox = Hive.box<BackupRule>(AppConstants.backupRulesBox);
      final rule = rulesBox.get('camera');

      if (rule == null || !rule.enabled) {
        AppLogger.d('AutoBackupScheduler: No enabled camera rule, skipping', tag: 'AutoBackupScheduler');
        return;
      }

      // Check eligibility
      final now = DateTime.now();
      final unmetered = await Connectivity.isUnmetered();
      final charging = await _deviceHardware.isCharging();

      final eligibility = evaluateEligibility(
        rule: rule,
        now: now,
        unmetered: unmetered,
        charging: charging,
        permissionGranted: true,
      );

      if (!eligibility.isEligible) {
        AppLogger.i('AutoBackupScheduler: Not eligible - ${eligibility.label}', tag: 'AutoBackupScheduler');
        return;
      }

      AppLogger.i('AutoBackupScheduler: Eligible, running backup', tag: 'AutoBackupScheduler');

      // Run backup with upload enqueue callback
      final result = await _backupService.runBackup(
        // Enqueue uploads to UploadBloc
        enqueuer: _enqueueToUploadBloc,
      );

      AppLogger.i('AutoBackupScheduler: Backup complete - ${result.summary}', tag: 'AutoBackupScheduler');

      // Notify callback
      if (_onRunComplete != null) {
        await _onRunComplete!(result);
      }

      // Show summary notification
      if (result.uploadedCount > 0 || result.errors.isNotEmpty) {
        await _showSummaryNotification(result);
      }
    } catch (e, st) {
      AppLogger.e('AutoBackupScheduler: Check failed: $e', tag: 'AutoBackupScheduler', error: e, stackTrace: st);
    } finally {
      _isRunning = false;
    }
  }

  /// Enqueues upload tasks to the UploadBloc.
  Future<void> _enqueueToUploadBloc(List<UploadTask> tasks) async {
    final bloc = _uploadBloc ?? ServiceLocator.instance.uploadBloc;
    if (bloc == null || bloc.isClosed) {
      AppLogger.w('AutoBackupScheduler: UploadBloc not available, cannot enqueue', tag: 'AutoBackupScheduler');
      return;
    }

    bloc.add(AddUploads(tasks));
    AppLogger.i('AutoBackupScheduler: Enqueued ${tasks.length} backup uploads', tag: 'AutoBackupScheduler');
  }

  /// Shows a summary notification after backup run.
  Future<void> _showSummaryNotification(BackupRunResult result) async {
    final plan = result.plan;
    String body;

    if (result.hasErrors) {
      body = 'Completed with ${result.errors.length} error(s). Uploaded ${result.uploadedCount} file(s).';
    } else if (plan.uploads.isEmpty && plan.accountedTotal == 0) {
      body = 'No new files to back up.';
    } else {
      final parts = <String>[];
      if (result.uploadedCount > 0) parts.add('${result.uploadedCount} uploaded');
      if (plan.skippedKnown > 0) parts.add('${plan.skippedKnown} unchanged');
      if (plan.skippedBackfill > 0) parts.add('${plan.skippedBackfill} pre-rule');
      if (plan.skippedCloudAdopted > 0) parts.add('${plan.skippedCloudAdopted} cloud-matched');
      if (plan.skippedType > 0) parts.add('${plan.skippedType} type-filtered');
      if (plan.skippedOversized > 0) parts.add('${plan.skippedOversized} oversized');
      body = parts.join(', ');
    }

    await NotificationService.instance.showCompletionNotification(
      title: 'Auto-Backup Complete',
      body: body,
      payload: 'auto_backup_summary',
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction('view_uploads', 'View Uploads', showsUserInterface: true),
      ],
    );
  }

  /// Stops the scheduler and cancels periodic tasks.
  Future<void> dispose() async {
    _periodicTimer?.cancel();
    _periodicTimer = null;

    try {
      await Workmanager().cancelByUniqueName(_autoBackupTaskName);
      AppLogger.i('AutoBackupScheduler: WorkManager task cancelled', tag: 'AutoBackupScheduler');
    } catch (e) {
      AppLogger.w('AutoBackupScheduler: WorkManager cancel failed: $e', tag: 'AutoBackupScheduler');
    }
  }
}

/// Background isolate entry point for WorkManager auto-backup task.
@pragma('vm:entry-point')
Future<void> _autoBackupBackgroundCallback() async {
  // This runs in a background isolate - we need to re-initialize minimal services
  // For now, we just log; full background execution would require service re-init
  debugPrint('AutoBackupScheduler: Background task triggered');
}