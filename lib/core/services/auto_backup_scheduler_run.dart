/*
 * File: auto_backup_scheduler_run.dart
 * Description: Manual and scheduled foreground backup execution orchestration.
 */
part of 'auto_backup_scheduler.dart';

extension AutoBackupSchedulerRuns on AutoBackupScheduler {
  /// Foreground run: consume the due flag, enqueue, watermark completions.
  ///
  /// Also the "Back up now" entry point ([manual]) and the app
  /// start/resume hook (killed-app recovery, C2). The due flag is consumed
  /// only after the rule passes eligibility, so an ineligible run (window,
  /// metered, not charging, permission) never loses the flag — it stays
  /// armed and is retried when conditions change. Uploads never run in the
  /// Workmanager isolate — this must be called on the main isolate only.
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

    final rule = _firstEnabledRule();
    if (rule == null) {
      return const BackupRunOutcome(
        status: BackupRunStatus.noRule,
        label: 'Off',
      );
    }

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

    // NOTE: Free-space gate intentionally removed — AutoBackup streams directly
    // from MediaStore paths to Telegram without local caching or disk duplication
    // (RawStreamChunker reads in-place, Mp4FastStartProjector uses virtual projection).
    // No temporary files or duplicated media are written to disk, so free space
    // is not a precondition for backup uploads.

    final planned = <String, BackupUploadItem>{};
    final tasks = <UploadTask>[];
    var alreadyActive = 0;
    var unresolved = 0;
    for (final upload in uploads) {
      final asset = upload.asset;
      final taskId =
          '${AutoBackupScheduler.taskIdPrefix}${asset.assetId}:${asset.fingerprint}';
      if (_isActive(taskId)) {
        alreadyActive++;
        continue;
      }
      final resolved = await _resolvePath(asset);
      if (resolved == null) {
        unresolved++;
        AppLogger.w(
            'Backup: could not resolve upload path for asset ${asset.assetId} (${asset.title}), skipping',
            tag: 'AutoBackupScheduler');
        continue;
      }
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

    final outcome = await _enqueueAndWatch(
      rule: rule,
      tasks: tasks,
      planned: planned,
      albumFolderId: albumFolderId,
      skippedUnresolvable: result.skippedUnresolvable + unresolved,
      backfillRequested: backfill,
      backfillPlanCapped: result.plan.capped,
      allPlannedResolved: unresolved == 0 && alreadyActive == 0,
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
    required int skippedUnresolvable,
    required bool backfillRequested,
    required bool backfillPlanCapped,
    required bool allPlannedResolved,
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
        }
      }
      if (pending.isNotEmpty) {
        await Future<void>.delayed(_pollInterval);
      }
    }

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
    return BackupRunOutcome(
      status: BackupRunStatus.ran,
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
