/*
 * File: auto_backup_scheduler_run.dart
 * Description: Manual and scheduled foreground backup execution orchestration.
 */
part of 'auto_backup_scheduler.dart';

/// Mutable per-run progress counters shared across rules.
class _BackupProgressTracker {
  int processed = 0;
  int total = 0;
}

extension AutoBackupSchedulerRuns on AutoBackupScheduler {
  /// Foreground run: consume the due flag, enqueue, watermark completions.
  ///
  /// Also the "Back up now" entry point ([manual]) and the app
  /// start/resume hook (killed-app recovery, C2). The due flag is consumed
  /// only after every enabled rule passes eligibility, so an ineligible run
  /// (window, metered, not charging, permission) never loses the flag — it
  /// stays armed and is retried when conditions change. Uploads never run in
  /// the Workmanager isolate — this must be called on the main isolate only.
  Future<BackupRunOutcome> consumeDueFlag({
    bool manual = false,
    bool backfill = false,
  }) async {
    if (_runInProgress) {
      return const BackupRunOutcome(
        status: BackupRunStatus.ineligible,
        label: 'A backup is already running',
      );
    }
    _runInProgress = true;
    _runProgress.value = const BackupRunProgress(scanning: true);
    AppLogger.i('Backup run started type=${manual ? 'manual' : 'scheduled'}',
        tag: 'AutoBackup');
    try {
      final outcome = await _consumeDueFlag(manual: manual, backfill: backfill);
      if (outcome.status == BackupRunStatus.ran && !outcome.needsRetry) {
        await _state.put(AppConstants.autoBackupDueKey, false);
      }
      final summary = 'Backup run result=${outcome.status.name} '
          'photos=${outcome.uploadedPhotos} videos=${outcome.uploadedVideos} '
          'skipped=${outcome.skippedUnresolvable}';
      if (outcome.status == BackupRunStatus.failed || outcome.needsRetry) {
        AppLogger.e('$summary reason=${backupDiagnosticFailure(outcome.label)}',
            tag: 'AutoBackup');
      } else {
        AppLogger.i(summary, tag: 'AutoBackup');
      }
      return outcome;
    } catch (e) {
      AppLogger.e(
          'Backup run result=failed reason=${backupDiagnosticFailure('$e')} exception=$e',
          tag: 'AutoBackup');
      return const BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: 'Backup run failed',
      );
    } finally {
      _runInProgress = false;
      _runProgress.value = null;
    }
  }

  Future<BackupRunOutcome> _consumeDueFlag({
    required bool manual,
    bool backfill = false,
  }) async {
    final due =
        _state.get(AppConstants.autoBackupDueKey, defaultValue: false) ?? false;
    if (!due && !manual) {
      return const BackupRunOutcome(
        status: BackupRunStatus.notDue,
        label: 'Not due',
      );
    }

    final rules = _rules.values.where((rule) => rule.enabled).toList();
    if (rules.isEmpty) {
      return const BackupRunOutcome(
        status: BackupRunStatus.noRule,
        label: 'Off',
      );
    }

    final tracker = _BackupProgressTracker();
    final outcomes = <BackupRunOutcome>[];
    var anyBackfillRequested = false;
    var allRequestedBackfillsComplete = true;
    for (final rule in rules) {
      final requested = backfill && !rule.backfillDone;
      final outcome = await _runRule(
        rule,
        manual: manual,
        backfill: requested,
        tracker: tracker,
      );
      outcomes.add(outcome);
      if (requested) {
        anyBackfillRequested = true;
        allRequestedBackfillsComplete =
            allRequestedBackfillsComplete && outcome.backfillComplete;
      }
    }
    return _mergeOutcomes(
      outcomes,
      backfillComplete: anyBackfillRequested && allRequestedBackfillsComplete,
    );
  }

  /// Combines per-rule outcomes; a single rule keeps its exact outcome.
  BackupRunOutcome _mergeOutcomes(
    List<BackupRunOutcome> outcomes, {
    required bool backfillComplete,
  }) {
    if (outcomes.length == 1) return outcomes.first;
    var photos = 0;
    var videos = 0;
    var skipped = 0;
    var needsRetry = false;
    var anyRan = false;
    var anyFailed = false;
    var anyIneligible = false;
    for (final outcome in outcomes) {
      photos += outcome.uploadedPhotos;
      videos += outcome.uploadedVideos;
      skipped += outcome.skippedUnresolvable;
      needsRetry = needsRetry || outcome.needsRetry;
      anyRan = anyRan || outcome.status == BackupRunStatus.ran;
      anyFailed = anyFailed || outcome.status == BackupRunStatus.failed;
      anyIneligible =
          anyIneligible || outcome.status == BackupRunStatus.ineligible;
    }
    final status = anyRan
        ? BackupRunStatus.ran
        : anyFailed
            ? BackupRunStatus.failed
            : anyIneligible
                ? BackupRunStatus.ineligible
                : outcomes.first.status;
    final label = anyRan
        ? (photos + videos > 0
            ? 'Backed up $photos photos, $videos videos'
            : 'Already up to date')
        : outcomes
            .firstWhere(
              (o) => o.status == status,
              orElse: () => outcomes.first,
            )
            .label;
    return BackupRunOutcome(
      status: status,
      label: label,
      uploadedPhotos: photos,
      uploadedVideos: videos,
      skippedUnresolvable: skipped,
      backfillComplete: backfillComplete,
      needsRetry: needsRetry,
    );
  }

  /// Runs one rule: eligibility, scan, path setup, enqueue, watermark.
  Future<BackupRunOutcome> _runRule(
    BackupRule rule, {
    required bool manual,
    required bool backfill,
    required _BackupProgressTracker tracker,
  }) async {
    // For manual "Back up now", bypass window/Wi-Fi/charging gates.
    // Keep enabled + permission checks (F2).
    final eligibility = manual
        ? await _activeService.isEligibleNowManual(rule)
        : await _activeService.isEligibleNow(rule);
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

    // Keep the due flag armed until a run succeeds. Failures in scanning,
    // path setup, disk checks, or uploads can then be retried.
    final collected = await _activeService.collectDueAssets(
      rule,
      includeBackfill: backfill,
    );
    if (collected.isFailure) {
      return BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: collected.failureOrNull?.message ?? 'Scan failed',
      );
    }
    final result = collected.dataOrNull!;
    final uploads = result.uploads;
    if (uploads.isEmpty) {
      final backfillComplete =
          backfill && !result.plan.capped && result.skippedUnresolvable == 0;
      if (backfillComplete) {
        rule.backfillDone = true;
        await rule.save();
      }
      return BackupRunOutcome(
        status: BackupRunStatus.ran,
        label: 'Already up to date',
        skippedUnresolvable: result.skippedUnresolvable,
        backfillComplete: backfillComplete,
        needsRetry: result.plan.capped || result.skippedUnresolvable > 0,
      );
    }

    final pathResult = await _activeService.ensureBackupPath(
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

    final freeSpace = await _activeService.ensureFreeSpaceFor(
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
    final destFolders = <String, String>{};
    final subfolderCache = <String, String>{};
    var alreadyActive = 0;
    var unresolved = 0;
    for (final upload in uploads) {
      final asset = upload.asset;
      final taskId =
          '${AutoBackupScheduler.taskIdPrefix}${asset.assetId}:${asset.fingerprint}';
      // Duplicate scan rows must never enqueue a second copy: the cloud
      // would receive it but the watermark counts unique task ids only.
      if (planned.containsKey(taskId)) continue;
      if (_isActive(taskId)) {
        alreadyActive++;
        continue;
      }
      final ({String path, bool isTemporary})? resolved;
      if (rule.isDirectory) {
        // Directory asset ids are absolute device paths — no MediaStore.
        resolved = (path: asset.assetId, isTemporary: false);
      } else {
        resolved = await _resolvePath(asset);
      }
      if (resolved == null) {
        unresolved++;
        continue;
      }
      var folderId = albumFolderId;
      if (rule.isDirectory) {
        final sub = await _activeService.ensureSubfolderPath(
          rule,
          asset.relativePath ?? '',
          cache: subfolderCache,
        );
        if (sub.isFailure) {
          return BackupRunOutcome(
            status: BackupRunStatus.failed,
            label: sub.failureOrNull?.message ?? 'Folder setup failed',
          );
        }
        folderId = sub.dataOrNull!;
        destFolders[asset.assetId] = folderId;
      }
      tasks.add(UploadTask(
        id: taskId,
        path: resolved.path,
        name: upload.destinationName,
        size: asset.sizeBytes,
        folderId: folderId,
        isTemporaryCacheFile: resolved.isTemporary,
      ));
      planned[taskId] = upload;
    }
    if (tasks.isEmpty) {
      if (unresolved > 0) {
        return BackupRunOutcome(
          status: BackupRunStatus.failed,
          label: 'Could not resolve $unresolved media file(s)',
          skippedUnresolvable: result.skippedUnresolvable + unresolved,
        );
      }
      return BackupRunOutcome(
        status: BackupRunStatus.ran,
        label: 'Already up to date',
        skippedUnresolvable: result.skippedUnresolvable,
        backfillComplete: backfill &&
            !result.plan.capped &&
            alreadyActive == 0 &&
            result.skippedUnresolvable == 0,
        needsRetry: result.plan.capped ||
            alreadyActive > 0 ||
            result.skippedUnresolvable > 0,
      );
    }

    tracker.total += tasks.length;
    final outcome = await _enqueueAndWatch(
      rule: rule,
      tasks: tasks,
      planned: planned,
      albumFolderId: albumFolderId,
      destFolderIdsByAssetId: destFolders,
      skippedUnresolvable: result.skippedUnresolvable + unresolved,
      backfillRequested: backfill,
      backfillPlanCapped: result.plan.capped,
      allPlannedResolved: unresolved == 0 && alreadyActive == 0,
      tracker: tracker,
    );
    if (outcome.backfillComplete) {
      rule.backfillDone = true;
      await rule.save();
    }
    return outcome;
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
    required Map<String, String> destFolderIdsByAssetId,
    required int skippedUnresolvable,
    required bool backfillRequested,
    required bool backfillPlanCapped,
    required bool allPlannedResolved,
    required _BackupProgressTracker tracker,
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
    var failedTasks = 0;
    final deadline = DateTime.now().add(_watchTimeout);

    while (pending.isNotEmpty && DateTime.now().isBefore(deadline)) {
      if (!rule.enabled) {
        for (final id in pending) {
          bloc.add(CancelUploadTask(id));
        }
        pending.clear();
        break;
      }
      var partialProgress = 0.0;
      String? currentFile;
      for (final id in pending.toList()) {
        final task = _findTask(id);
        if (task == null) continue;
        if (task.status == TransferStatus.completed) {
          completedIds.add(id);
          pending.remove(id);
        } else if (task.status == TransferStatus.failed ||
            task.status == TransferStatus.cancelled) {
          failedTasks++;
          pending.remove(id);
        } else {
          partialProgress += task.progress.clamp(0.0, 1.0).toDouble();
          if (currentFile == null && task.status == TransferStatus.uploading) {
            currentFile = task.name;
          }
        }
      }
      final processed =
          tracker.processed + completedIds.length + failedTasks;
      _runProgress.value = BackupRunProgress(
        completed: processed,
        total: tracker.total,
        fraction: tracker.total == 0
            ? 0.0
            : ((processed + partialProgress) / tracker.total)
                .clamp(0.0, 1.0)
                .toDouble(),
        currentFileName: currentFile,
      );
      if (pending.isNotEmpty) {
        await Future<void>.delayed(_pollInterval);
      }
    }
    tracker.processed += completedIds.length + failedTasks;

    var photos = 0;
    var videos = 0;
    var watermarkFailed = false;
    if (completedIds.isNotEmpty) {
      final destIds = <String, String>{
        for (final id in completedIds) planned[id]!.asset.assetId: id,
      };
      final completedUploads = completedIds.map((id) => planned[id]!).toList();
      final watermark = await _activeService.advanceWatermark(
        rule: rule,
        uploads: completedUploads,
        destFileIdsByAssetId: destIds,
        destFolderId: albumFolderId,
        destFolderIdsByAssetId: destFolderIdsByAssetId,
      );
      watermarkFailed = watermark.isFailure;
      for (final upload in completedUploads) {
        if (upload.asset.isVideo) {
          videos++;
        } else {
          photos++;
        }
      }
    }

    await _activeService.enforceRetention(rule);

    if (photos + videos > 0) {
      await _notify(
        'Backup complete',
        'Backed up $photos photos, $videos videos',
      );
    }

    final complete = pending.isEmpty &&
        failedTasks == 0 &&
        !watermarkFailed &&
        allPlannedResolved &&
        skippedUnresolvable == 0 &&
        !backfillPlanCapped;
    final label = watermarkFailed
        ? 'Backup uploaded, but completion could not be recorded'
        : failedTasks > 0
            ? '$failedTasks upload(s) failed'
            : pending.isNotEmpty
                ? '${pending.length} upload(s) still pending'
                : 'Backed up $photos photos, $videos videos';
    final hasFailed = (photos == 0 && videos == 0 && failedTasks > 0) ||
        (tasks.isNotEmpty && completedIds.isEmpty && failedTasks > 0);
    return BackupRunOutcome(
      status: hasFailed ? BackupRunStatus.failed : BackupRunStatus.ran,
      label: label,
      uploadedPhotos: photos,
      uploadedVideos: videos,
      skippedUnresolvable: skippedUnresolvable,
      backfillComplete: backfillRequested && complete,
      needsRetry: failedTasks > 0 ||
          pending.isNotEmpty ||
          backfillPlanCapped ||
          !allPlannedResolved ||
          skippedUnresolvable > 0 ||
          watermarkFailed,
    );
  }
}