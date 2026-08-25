/*
 * File: download_queue_service.dart
 * Description: Component and logic definition for download_queue_service.dart in TelStorage.
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
import 'transfer_queue_service.dart';
import 'service_locator.dart';
import '../models/transfer_task.dart';
import '../utils/local_file_stub.dart'
    if (dart.library.io) '../utils/local_file_native.dart';

/// Manages concurrent downloads (max 3), queue, and state persistence using Hive.
class DownloadQueueService {
  final DownloadService _downloadService;
  final String _boxName;

  DownloadQueueService(this._downloadService, this._boxName);

  Box<DownloadJob> get _box => Hive.box<DownloadJob>(_boxName);

  // Active downloads tracking for cancellation
  final Map<String, bool> _activeCancellationTokens = {};

  // Track currently downloading futures to manage concurrency limit (max 3)
  final Set<String> _runningFileIds = {};

  /// ValueNotifier / ValueListenable to expose the list of jobs
  ValueListenable<Box<DownloadJob>> get listenable => _box.listenable();

  List<DownloadJob> get allJobs =>
      _box.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  List<DownloadJob> get activeJobs => _box.values
      .where((j) => j.status == 'queued' || j.status == 'downloading')
      .toList();

  List<DownloadJob> get completedJobs =>
      _box.values.where((j) => j.status == 'completed').toList();

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

  /// Add a new download job or resume an existing failed/cancelled one
  Future<void> enqueueDownload(FileRecord file) async {
    final existingJob = _box.get(file.fileId);

    if (existingJob != null) {
      if (existingJob.status == 'completed') {
        AppLogger.i('File already downloaded: ${file.name}',
            tag: 'DownloadQueue');
        return;
      }
      // If already queued or downloading, do nothing
      if (existingJob.status == 'queued' ||
          existingJob.status == 'downloading') {
        return;
      }
      // Resume/retry failed or cancelled job
      existingJob.status = 'queued';
      existingJob.progress = 0.0;
      existingJob.error = null;
      await existingJob.save();
    } else {
      // Create new job
      final job = DownloadJob(
        fileId: file.fileId,
        name: file.name,
        mimeType: file.mimeType,
        sizeMb: file.sizeMb,
        progress: 0.0,
        status: 'queued',
        addedAt: DateTime.now(),
      );
      await _box.put(file.fileId, job);
    }

    // Add to unified transfer queue
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
    _processQueue();
  }

  /// Cancel an ongoing download or remove from queue
  Future<void> cancelDownload(String fileId) async {
    final job = _box.get(fileId);
    if (job == null) return;

    if (job.status == 'queued') {
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
    await removeJob(fileId);
  }

  /// Clear all completed downloads from history
  Future<void> clearCompletedHistory() async {
    final completed = completedJobs;
    for (final job in completed) {
      await _box.delete(job.fileId);
    }
  }

  /// Restarts queued work after an app relaunch. A previously running download
  /// has no live network request to resume, so it is safely restarted from the
  /// beginning using its persisted metadata.
  Future<void> resumePendingDownloads() async {
    for (final job in _box.values) {
      if (job.status == 'queued' || job.status == 'downloading') {
        job.status = 'queued';
        await job.save();
        _activeCancellationTokens[job.fileId] = false;
      }
    }
    _processQueue();
  }

  /// Manually add a completed download job (used for direct downloads)
  Future<void> addCompletedJob(FileRecord file, String? savedPath) async {
    final job = DownloadJob(
      fileId: file.fileId,
      name: file.name,
      mimeType: file.mimeType,
      sizeMb: file.sizeMb,
      progress: 1.0,
      status: 'completed',
      localPath: savedPath,
      completedAt: DateTime.now(),
      addedAt: DateTime.now(),
    );
    await _box.put(file.fileId, job);
  }

  /// Process the queue managing concurrency limit (max 3 concurrent downloads)
  void _processQueue() {
    if (_runningFileIds.length >= 3) return;

    final queuedJobs = _box.values.where((j) => j.status == 'queued').toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));

    for (final job in queuedJobs) {
      if (_runningFileIds.length >= 3) break;

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
        body: 'Failed to download ${job.name}: no internet connection.',
      );

      _runningFileIds.remove(fileId);
      _processQueue();
      return;
    }

    try {
      final bytes = await _downloadService.downloadFile(fileRecord,
          (progress, status) async {
        if (_isCancelled(fileId)) {
          throw Exception('Cancelled');
        }
        job.progress = progress;
        await job.save();

        TransferQueueService.instance.updateTask(fileId,
            progress: progress, currentStage: 'Downloading…');
      });

      if (_isCancelled(fileId)) {
        throw Exception('Cancelled');
      }

      job.progress = 0.95;
      await job.save();
      TransferQueueService.instance
          .updateTask(fileId, progress: 0.95, currentStage: 'Finalizing…');

      final saveResult = await _downloadService.saveAndOpen(bytes, job.name);

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
              AndroidNotificationAction('open_${job.fileId}', 'Open File'),
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
          body: 'Failed to download ${job.name}: ${saveResult.message}',
        );
      }
    } catch (e) {
      if (_isCancelled(fileId)) {
        job.status = 'cancelled';
        TransferQueueService.instance
            .updateTask(fileId, status: TransferStatus.cancelled);
      } else {
        job.status = 'failed';
        job.error = e.toString();
        TransferQueueService.instance.updateTask(fileId,
            status: TransferStatus.failed, error: e.toString());

        await NotificationService.instance.showCompletionNotification(
          title: 'Download Failed',
          body: 'Failed to download ${job.name}: $e',
        );
      }
      await job.save();
    } finally {
      _runningFileIds.remove(fileId);
      _activeCancellationTokens.remove(fileId);
      _processQueue();
    }
  }
}
