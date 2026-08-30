/*
 * File: transfer_queue_service.dart
 * Description: Master transfer queue orchestrator managing active upload/download progress, speed calculations, pause/resume delegates, and persisted state loading.
 */

import 'package:flutter/foundation.dart';
import '../models/transfer_task.dart';
import 'notification_service.dart';
import 'service_locator.dart';

/// Central singleton service orchestrating real-time transfer states, speed metrics, and background task progress.
class TransferQueueService {
  TransferQueueService._();

  /// Global singleton instance.
  static final TransferQueueService instance = TransferQueueService._();

  final ValueNotifier<List<TransferTask>> _tasksNotifier = ValueNotifier([]);

  /// Listenable stream of active and historical transfer tasks.
  ValueListenable<List<TransferTask>> get tasksNotifier => _tasksNotifier;

  final Map<String, DateTime> _lastUpdateTimes = {};
  final Map<String, double> _lastProgresses = {};

  /// All recorded transfer tasks in memory.
  List<TransferTask> get tasks => _tasksNotifier.value;

  /// Filtered active transfers that are not completed, failed, or cancelled.
  List<TransferTask> get activeTasks => tasks.where((t) => t.isActive).toList();

  /// Enqueues a new transfer task or updates an existing entry.
  void addTask(TransferTask task) {
    final newTasks = List<TransferTask>.from(tasks);
    final existingIndex =
        newTasks.indexWhere((existing) => existing.id == task.id);
    if (existingIndex == -1) {
      newTasks.add(task);
    } else {
      newTasks[existingIndex] = task;
    }
    _tasksNotifier.value = newTasks;
    _updateNotification();
  }

  /// Updates progress, status, error, and ETA metrics for a running transfer task.
  void updateTask(
    String id, {
    double? progress,
    TransferStatus? status,
    String? currentStage,
    String? error,
  }) {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = tasks[index];

    // Calculate speed and ETA if progress changed
    double speed = task.speedKbps;
    String? eta = task.eta;

    if (progress != null && progress > task.progress) {
      final now = DateTime.now();
      final lastTime = _lastUpdateTimes[id];
      final lastProgress = _lastProgresses[id] ?? task.progress;

      if (lastTime != null) {
        final duration = now.difference(lastTime).inMilliseconds;
        if (duration >= 500) {
          // Update speed every 500ms
          final progressDelta = progress - lastProgress;
          final sizeDeltaKb = progressDelta * task.sizeMb * 1024;
          final durationSec = duration / 1000.0;
          if (durationSec > 0 && sizeDeltaKb > 0) {
            final calculatedSpeed = sizeDeltaKb / durationSec;
            if (calculatedSpeed.isFinite && !calculatedSpeed.isNaN && calculatedSpeed > 0) {
              speed = calculatedSpeed;
            }
          }

          if (speed > 0 && speed.isFinite) {
            final remainingMb = (1.0 - progress) * task.sizeMb;
            final remainingSeconds = (remainingMb * 1024) / speed;
            if (remainingSeconds.isFinite && remainingSeconds > 0) {
              eta = _formatDuration(Duration(seconds: remainingSeconds.toInt()));
            }
          }

          _lastUpdateTimes[id] = now;
          _lastProgresses[id] = progress;
        }
      } else {
        _lastUpdateTimes[id] = now;
        _lastProgresses[id] = progress;
      }
    }

    final updatedTask = task.copyWith(
      progress: progress,
      status: status,
      currentStage: currentStage,
      error: error,
      completedAt: status == TransferStatus.completed ? DateTime.now() : null,
      speedKbps: speed,
      eta: eta,
    );

    final newTasks = List<TransferTask>.from(tasks);
    newTasks[index] = updatedTask;
    _tasksNotifier.value = newTasks;

    _updateNotification();
  }

  /// Removes a task from the active queue.
  void removeTask(String id) {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index != -1) {
      final task = tasks[index];
      if (task.isActive) {
        updateTask(id, status: TransferStatus.cancelled);
      }
    }

    final newTasks = List<TransferTask>.from(tasks)
      ..removeWhere((t) => t.id == id);
    _tasksNotifier.value = newTasks;
    _lastUpdateTimes.remove(id);
    _lastProgresses.remove(id);
    _updateNotification();
  }

  /// Clears all tasks from memory (for testing or full reset).
  void clearAll() {
    _tasksNotifier.value = [];
    _lastUpdateTimes.clear();
    _lastProgresses.clear();
  }

  /// Requests cancellation while retaining the task long enough for its
  /// underlying service to observe the state and clean up correctly.
  void cancelTask(String id) {
    updateTask(id, status: TransferStatus.cancelled, currentStage: 'Cancelled');
    try {
      if (ServiceLocator.instance.isInitialized) {
        ServiceLocator.instance.downloadQueue.cancelDownload(id);
      }
    } catch (_) {}
  }

  /// Pauses an active transfer and delegates to underlying queue service.
  void pauseTask(String id) {
    updateTask(id, status: TransferStatus.paused, currentStage: 'Paused');
    try {
      if (ServiceLocator.instance.isInitialized) {
        ServiceLocator.instance.downloadQueue.pauseDownload(id);
      }
    } catch (_) {}
  }

  /// Resumes a paused transfer and delegates to underlying queue service.
  void resumeTask(String id) {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = tasks[index];
    final newStatus = task.type == TransferType.upload
        ? TransferStatus.uploading
        : (task.type == TransferType.download
            ? TransferStatus.downloading
            : TransferStatus.sharing);

    updateTask(id, status: newStatus, currentStage: 'Resuming...');
    try {
      if (ServiceLocator.instance.isInitialized) {
        if (task.type == TransferType.download) {
          ServiceLocator.instance.downloadQueue.resumeDownload(id);
        }
      }
    } catch (_) {}
  }

  /// Checks if a task is currently in paused state.
  bool isPaused(String id) {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index == -1) return false;
    return tasks[index].status == TransferStatus.paused;
  }

  /// Checks if a task is currently in cancelled state.
  /// Returns false for unknown task IDs (e.g., file downloads invoked
  /// outside the queue, such as ZIP export sub-downloads).
  bool isCancelled(String id) {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index == -1) return false;
    return tasks[index].status == TransferStatus.cancelled;
  }

  void _updateNotification() {
    final active = activeTasks;
    NotificationService.instance.updateTransferNotification(active);
  }

  String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  /// Restores persisted tasks from DownloadQueue and WebShareQueue upon app relaunch.
  void loadFromPersistence() {
    List<TransferTask> persistedTasks = [];
    try {
      if (ServiceLocator.instance.isInitialized) {
        final downloads = ServiceLocator.instance.downloadQueue.activeJobs;
        final shares = ServiceLocator.instance.webShareQueue.allShares
            .where((s) => !s.isComplete && !s.isFailed && !s.isCancelled)
            .toList();

        for (final j in downloads) {
          TransferStatus taskStatus;
          if (j.status == 'paused') {
            taskStatus = TransferStatus.paused;
          } else if (j.status == 'downloading') {
            taskStatus = TransferStatus.downloading;
          } else {
            taskStatus = TransferStatus.pending;
          }

          persistedTasks.add(TransferTask(
            id: j.fileId,
            name: j.name,
            type: TransferType.download,
            sizeMb: j.sizeMb,
            progress: j.progress,
            status: taskStatus,
            currentStage: j.status == 'paused' ? 'Paused' : 'Waiting in queue…',
            addedAt: j.addedAt,
          ));
        }

        for (final j in shares) {
          persistedTasks.add(TransferTask(
            id: j.fileId,
            name: j.name,
            type: TransferType.share,
            sizeMb: j.sizeMb,
            progress: j.progress,
            status: j.isDownloading
                ? TransferStatus.downloading
                : (j.isUploading
                    ? TransferStatus.sharing
                    : TransferStatus.pending),
            addedAt: j.addedAt,
          ));
        }
      }
    } catch (e) {
      // Fallback gracefully on initialization boundaries
    }

    _tasksNotifier.value = persistedTasks;
    _updateNotification();
  }

  /// Clears active tasks from in-memory notifier.
  void clear() {
    _tasksNotifier.value = [];
    _lastUpdateTimes.clear();
    _lastProgresses.clear();
  }
}
