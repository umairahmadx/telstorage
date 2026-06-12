import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/download_job.dart';
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import 'download_service.dart';
import 'notification_service.dart';
import 'service_locator.dart';

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

  /// Check if a download is cancelled
  bool isCancelled(String fileId) => _activeCancellationTokens[fileId] == true;

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
    _runningFileIds.remove(fileId);
    _processQueue();
  }

  /// Delete a job history
  Future<void> removeJob(String fileId) async {
    await cancelDownload(fileId);
    await _box.delete(fileId);
  }

  /// Clear all completed downloads from history
  Future<void> clearCompletedHistory() async {
    final completed = completedJobs;
    for (final job in completed) {
      await _box.delete(job.fileId);
    }
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
      _runningFileIds.remove(fileId);
      _processQueue();
      return;
    }

    job.status = 'downloading';
    job.progress = 0.0;
    await job.save();

    if (!await Connectivity.hasConnection()) {
      job.status = 'failed';
      job.error = 'No internet connection';
      await job.save();

      await NotificationService.instance.showNotification(
        id: fileId.hashCode,
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
        if (isCancelled(fileId)) {
          throw Exception('Cancelled');
        }
        job.progress = progress;
        await job.save();
      });

      if (isCancelled(fileId)) {
        throw Exception('Cancelled');
      }

      job.progress = 0.95;
      await job.save();

      final saveResult = await _downloadService.saveAndOpen(bytes, job.name);

      if (saveResult.success) {
        job.status = 'completed';
        job.progress = 1.0;
        job.localPath = saveResult.savedPath;
        job.completedAt = DateTime.now();
        await job.save();

        await NotificationService.instance.showNotification(
          id: fileId.hashCode,
          title: 'Download Complete',
          body: '${job.name} has been successfully downloaded.',
        );
      } else {
        job.status = 'failed';
        job.error = saveResult.message;
        await job.save();

        await NotificationService.instance.showNotification(
          id: fileId.hashCode,
          title: 'Download Failed',
          body: 'Failed to download ${job.name}: ${saveResult.message}',
        );
      }
    } catch (e) {
      if (isCancelled(fileId)) {
        job.status = 'cancelled';
      } else {
        job.status = 'failed';
        job.error = e.toString();

        await NotificationService.instance.showNotification(
          id: fileId.hashCode,
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
