/*
 * File: download_queue_service.dart
 * Description: Manages concurrent downloads (max 3), queue lifecycle, pause/resume, and Hive state persistence across app restarts.
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/download_job.dart';
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import 'download_service.dart';
import 'notification_service.dart';
import 'transfer_concurrency_coordinator.dart';
import 'transfer_queue_service.dart';
import 'service_locator.dart';
import '../models/transfer_task.dart';
import '../utils/local_file_stub.dart'
    if (dart.library.io) '../utils/local_file_native.dart';
import '../utils/native_save_stub.dart'
    if (dart.library.io) '../utils/native_save_helper.dart';

/// Manages concurrent downloads (max 3), queue, and state persistence using Hive.
class DownloadQueueService {
  final DownloadService _downloadService;
  final String _boxName;

  DownloadQueueService(this._downloadService, this._boxName);

  Box<DownloadJob> get _box => Hive.box<DownloadJob>(_boxName);

  // Active downloads tracking for cancellation and pause
  final Map<String, bool> _activeCancellationTokens = {};
  final Map<String, bool> _activePauseTokens = {};

  // Transient in-memory conflict policy map per fileId
  final Map<String, DownloadConflictPolicy> _inFlightPolicies = {};

  // Track currently downloading futures to manage concurrency limit (max 3)
  final Set<String> _runningFileIds = {};

  /// ValueNotifier / ValueListenable to expose the list of jobs
  ValueListenable<Box<DownloadJob>> get listenable => _box.listenable();

  List<DownloadJob> get allJobs =>
      _box.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  List<DownloadJob> get activeJobs => _box.values
      .where((j) =>
          j.status == 'queued' ||
          j.status == 'downloading' ||
          j.status == 'paused')
      .toList();

  List<DownloadJob> get completedJobs =>
      _box.values.where((j) => j.status == 'completed').toList();

  /// Returns the local path if file has been completed and exists on disk, otherwise null.
  String? getCompletedPath(String fileId) {
    final job = _box.get(fileId);
    if (job != null &&
        job.isComplete &&
        job.localPath != null &&
        checkLocalFileExists(job.localPath!)) {
      return job.localPath;
    }
    return null;
  }

  /// Check if a file is already downloaded and exists locally.
  bool isFileDownloaded(String fileId) => getCompletedPath(fileId) != null;

  /// Returns transient conflict policy configured for an in-flight fileId.
  DownloadConflictPolicy getConflictPolicy(String fileId) =>
      _inFlightPolicies[fileId] ?? DownloadConflictPolicy.overwrite;

  /// Checks whether a file with the given record already exists in download history or on disk.
  Future<bool> checkFileConflict(FileRecord file, {String? subpath}) async {
    final existingJob = _box.get(file.fileId);
    if (existingJob != null && existingJob.isComplete) return true;
    if (!kIsWeb) return doesTargetFileExist(file.name, subpath: subpath);
    return false;
  }

  /// Clears all completed download job records.
  Future<void> clearCompleted() async {
    final completed = completedJobs;
    for (final job in completed) {
      await _box.delete(job.fileId);
    }
  }

  /// Check if a download is cancelled
  bool isCancelled(String fileId) => _activeCancellationTokens[fileId] == true;

  bool _isCancelled(String fileId) =>
      isCancelled(fileId) || TransferQueueService.instance.isCancelled(fileId);

  /// Check if a download is paused
  bool isPaused(String fileId) =>
      _activePauseTokens[fileId] == true ||
      TransferQueueService.instance.isPaused(fileId);

  /// Add a new download job or resume an existing failed/cancelled one
  Future<void> enqueueDownload(
    FileRecord file, {
    String? subpath,
    DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
  }) async {
    _inFlightPolicies[file.fileId] = policy;
    final existingJob = _box.get(file.fileId);

    if (existingJob != null) {
      if (existingJob.status == 'queued' ||
          existingJob.status == 'downloading') {
        return;
      }
      if (existingJob.isComplete) {
        if (policy == DownloadConflictPolicy.skip) {
          AppLogger.i('Skipping existing download: ${file.name}',
              tag: 'DownloadQueue');
          return;
        }
      }
      existingJob.status = 'queued';
      existingJob.progress = 0.0;
      existingJob.error = null;
      await existingJob.save();
    } else {
      final job = DownloadJob(
        fileId: file.fileId,
        name: file.name,
        mimeType: file.mimeType,
        sizeMb: file.sizeMb,
        progress: 0.0,
        status: 'queued',
        addedAt: DateTime.now(),
        subpath: subpath,
      );
      await _box.put(file.fileId, job);
    }

    TransferQueueService.instance.addTask(TransferTask(
      id: file.fileId,
      name: file.name,
      type: TransferType.download,
      sizeMb: file.sizeMb,
      addedAt: DateTime.now(),
      status: TransferStatus.pending,
      currentStage: 'Waiting in queue…',
    ));

    _activeCancellationTokens[file.fileId] = false;
    _activePauseTokens[file.fileId] = false;
    _processQueue();
  }

  /// Pause an ongoing or queued download.
  Future<void> pauseDownload(String fileId) async {
    final job = _box.get(fileId);
    if (job == null) return;

    job.status = 'paused';
    await job.save();
    _activePauseTokens[fileId] = true;
    _runningFileIds.remove(fileId);

    TransferQueueService.instance.updateTask(
      fileId,
      status: TransferStatus.paused,
      currentStage: 'Paused',
    );
    _processQueue();
  }

  /// Resumes a paused or failed download.
  Future<void> resumeDownload(String fileId) async {
    final job = _box.get(fileId);
    if (job == null || job.status == 'completed') return;

    job.status = 'queued';
    job.error = null;
    await job.save();
    _activePauseTokens[fileId] = false;
    _activeCancellationTokens[fileId] = false;

    TransferQueueService.instance.updateTask(
      fileId,
      status: TransferStatus.pending,
      currentStage: 'Waiting in queue…',
    );
    _processQueue();
  }

  /// Cancel an ongoing download or remove from queue
  Future<void> cancelDownload(String fileId) async {
    final job = _box.get(fileId);
    if (job == null) return;

    if (job.status == 'queued' || job.status == 'paused') {
      job.status = 'cancelled';
      await job.save();
    } else if (job.status == 'downloading') {
      _activeCancellationTokens[fileId] = true;
      job.status = 'cancelled';
      await job.save();
    }
    TransferQueueService.instance
        .updateTask(fileId, status: TransferStatus.cancelled);
    _runningFileIds.remove(fileId);
    _processQueue();
  }

  /// Delete a job history
  Future<void> removeJob(String fileId) async {
    await cancelDownload(fileId);
    await _box.delete(fileId);
  }

  /// Delete a job and its local file from disk.
  Future<void> deleteJobAndLocalFile(String fileId) async {
    final job = _box.get(fileId);
    if (job != null && job.localPath != null && !kIsWeb) {
      try {
        if (await deleteLocalFileIfExists(job.localPath!)) {
          AppLogger.i('Deleted local file: ${job.localPath}',
              tag: 'DownloadQueue');
        }
      } catch (e) {
        AppLogger.w('Could not delete local file: $e', tag: 'DownloadQueue');
      }
    }
    try {
      await removeJob(fileId);
    } catch (e) {
      AppLogger.e('Could not remove download job from Hive: $e',
          tag: 'DownloadQueue');
    }
  }

  /// Adds or updates a ZIP export download job in Hive with idempotent upsert semantics.
  Future<void> addOrUpdateZipJob({
    required String fileId,
    required String name,
    required String mimeType,
    required double sizeMb,
    required String status,
    double progress = 0.0,
    String? localPath,
    String? error,
    DateTime? addedAt,
    DateTime? completedAt,
    String? subpath,
  }) async {
    final existing = _box.get(fileId);
    if (existing != null) {
      existing.status = status;
      existing.progress = progress;
      if (localPath != null) existing.localPath = localPath;
      existing.error = (status == 'downloading' || status == 'completed')
          ? null
          : (error ?? existing.error);
      if (completedAt != null) existing.completedAt = completedAt;
      await existing.save();
    } else {
      final job = DownloadJob(
        fileId: fileId,
        name: name,
        mimeType: mimeType,
        sizeMb: sizeMb,
        status: status,
        progress: progress,
        localPath: localPath,
        error: error,
        addedAt: addedAt ?? DateTime.now(),
        completedAt: completedAt,
        subpath: subpath,
      );
      await _box.put(fileId, job);
    }
  }

  /// Clear all completed downloads from history
  Future<void> clearCompletedHistory() async {
    for (final job in completedJobs) {
      await _box.delete(job.fileId);
    }
  }

  /// Restarts queued work after an app relaunch using persisted metadata.
  Future<void> resumePendingDownloads() async {
    unawaited(cleanStaleTempFiles());
    for (final job in _box.values) {
      if (job.status == 'downloading' || job.status == 'queued') {
        if (job.status == 'downloading') {
          job.status = 'queued';
          await job.save();
        }
        _activeCancellationTokens[job.fileId] = false;
        _activePauseTokens[job.fileId] = false;
      }
    }
    _processQueue();
  }

  /// Manually add a completed download job (used for direct downloads)
  Future<void> addCompletedJob(FileRecord file, String? savedPath) async {
    await _box.put(
      file.fileId,
      DownloadJob(
        fileId: file.fileId,
        name: file.name,
        mimeType: file.mimeType,
        sizeMb: file.sizeMb,
        progress: 1.0,
        status: 'completed',
        localPath: savedPath,
        completedAt: DateTime.now(),
        addedAt: DateTime.now(),
      ),
    );
  }

  /// Process the queue managing concurrency limit across global coordinator
  void _processQueue() {
    final available = TransferConcurrencyCoordinator.instance.maxConcurrent -
        TransferConcurrencyCoordinator.instance.activeCount;
    if (available <= 0) return;

    final queuedJobs = _box.values.where((j) => j.status == 'queued').toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));

    for (final job in queuedJobs) {
      if (_runningFileIds.length >= available) break;

      final fileId = job.fileId;
      _runningFileIds.add(fileId);
      _startDownload(job);
    }
  }

  Future<void> _startDownload(DownloadJob job) async {
    final fileId = job.fileId;

    // Retrieve FileRecord from Hive
    final fileRecord = ServiceLocator.instance.hive.getFile(fileId);
    if (fileRecord == null) {
      job.status = 'failed';
      job.error = 'File metadata not found locally';
      await job.save();
      TransferQueueService.instance.updateTask(
        fileId,
        status: TransferStatus.failed,
        error: job.error,
      );
      _runningFileIds.remove(fileId);
      _processQueue();
      return;
    }

    job.status = 'downloading';
    job.progress = 0.0;
    await job.save();

    TransferQueueService.instance.updateTask(fileId,
        status: TransferStatus.downloading, currentStage: 'Downloading…');

    if (!await Connectivity.hasConnection()) {
      job.status = 'failed';
      job.error = 'No internet connection';
      await job.save();

      TransferQueueService.instance.updateTask(fileId,
          status: TransferStatus.failed, error: 'No internet connection');

      await NotificationService.instance.showCompletionNotification(
        title: 'Download Failed',
        body: 'Failed to download ${job.name}',
        bigText: 'Failed to download ${job.name}\n\nError: No internet connection.',
      );

      _runningFileIds.remove(fileId);
      _processQueue();
      return;
    }

    await TransferConcurrencyCoordinator.instance.runGuarded(() async {
      try {
        final bytes = await _downloadService.downloadFile(fileRecord,
            (progress, status) async {
          if (_isCancelled(fileId)) {
            throw Exception('Cancelled');
          }
          if (isPaused(fileId)) {
            throw Exception('Paused');
          }
          job.progress = progress;
          await job.save();

          TransferQueueService.instance.updateTask(fileId,
              progress: progress, currentStage: 'Downloading…');
        });

        if (_isCancelled(fileId)) {
          throw Exception('Cancelled');
        }
        if (isPaused(fileId)) {
          throw Exception('Paused');
        }

        job.progress = 0.95;
        await job.save();
        final policy =
            _inFlightPolicies[fileId] ?? DownloadConflictPolicy.overwrite;
        final saveResult = await _downloadService.saveAndOpen(
          bytes,
          job.name,
          subpath: job.subpath,
          policy: policy,
        );

        if (saveResult.success) {
          job.status = 'completed';
          job.progress = 1.0;
          job.localPath = saveResult.savedPath;
          job.completedAt = DateTime.now();
          await job.save();

          TransferQueueService.instance.updateTask(fileId,
              status: TransferStatus.completed, progress: 1.0);

          await NotificationService.instance.showCompletionNotification(
            title: 'Download Complete',
            body: '${job.name} has been successfully downloaded.',
            payload: 'transfer_download',
            actions: [
              if (saveResult.savedPath != null)
                AndroidNotificationAction('open_path:${saveResult.savedPath}',
                    'Open File', showsUserInterface: true),
              const AndroidNotificationAction(
                  'view_downloads', 'View Downloads', showsUserInterface: true),
            ],
          );
        } else {
          job.status = 'failed';
          job.error = saveResult.message;
          await job.save();

          TransferQueueService.instance.updateTask(fileId,
              status: TransferStatus.failed, error: saveResult.message);

          await NotificationService.instance.showCompletionNotification(
            title: 'Download Failed',
            body: 'Failed to download ${job.name}',
            bigText: 'Failed to download ${job.name}\n\nError: ${saveResult.message}',
            payload: 'transfer_download',
          );
        }
      } catch (e) {
        if (_isCancelled(fileId)) {
          job.status = 'cancelled';
          try { await job.save(); } catch (_) {}
          TransferQueueService.instance
              .updateTask(fileId, status: TransferStatus.cancelled);
        } else if (isPaused(fileId) || e.toString().contains('Paused')) {
          job.status = 'paused';
          try { await job.save(); } catch (_) {}
          TransferQueueService.instance.updateTask(fileId,
              status: TransferStatus.paused, currentStage: 'Paused');
        } else {
          job.status = 'failed';
          job.error = e.toString();
          try { await job.save(); } catch (_) {}
          TransferQueueService.instance.updateTask(fileId,
              status: TransferStatus.failed, error: e.toString());

          await NotificationService.instance.showCompletionNotification(
            title: 'Download Failed',
            body: 'Failed to download ${job.name}',
            bigText: 'Failed to download ${job.name}\n\nError: $e',
            payload: 'transfer_download',
          );
        }
      } finally {
        _inFlightPolicies.remove(fileId);
        _runningFileIds.remove(fileId);
        _activeCancellationTokens.remove(fileId);
        _activePauseTokens.remove(fileId);
        _processQueue();
      }
    });
  }
}
