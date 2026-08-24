/// File: transfer_queue_service.dart
/// Description: Component and logic definition for transfer_queue_service.dart in TelStorage.
library;

import 'package:flutter/foundation.dart';
import '../models/transfer_task.dart';
import 'notification_service.dart';
import 'service_locator.dart';

class TransferQueueService {
  TransferQueueService._();
  static final TransferQueueService instance = TransferQueueService._();

  final ValueNotifier<List<TransferTask>> _tasksNotifier = ValueNotifier([]);
  ValueListenable<List<TransferTask>> get tasksNotifier => _tasksNotifier;

  final Map<String, DateTime> _lastUpdateTimes = {};
  final Map<String, double> _lastProgresses = {};

  List<TransferTask> get tasks => _tasksNotifier.value;
  List<TransferTask> get activeTasks => tasks.where((t) => t.isActive).toList();

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
        if (duration > 500) {
          // Update speed every 500ms
          final progressDelta = progress - lastProgress;
          final sizeDeltaKb = progressDelta * task.sizeMb * 1024;
          speed = (sizeDeltaKb / (duration / 1000.0));

          if (speed > 0) {
            final remainingMb = (1.0 - progress) * task.sizeMb;
            final remainingSeconds = (remainingMb * 1024) / speed;
            eta = _formatDuration(Duration(seconds: remainingSeconds.toInt()));
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

  /// Requests cancellation while retaining the task long enough for its
  /// underlying service to observe the state and clean up correctly.
  void cancelTask(String id) {
    updateTask(id, status: TransferStatus.cancelled, currentStage: 'Cancelled');
  }

  void pauseTask(String id) {
    updateTask(id, status: TransferStatus.paused, currentStage: 'Paused');
  }

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
  }

  bool isPaused(String id) {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index == -1) return false;
    return tasks[index].status == TransferStatus.paused;
  }

  bool isCancelled(String id) {
    final index = tasks.indexWhere((t) => t.id == id);
    if (index == -1) return true; // Treat as cancelled if removed
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

  void loadFromPersistence() {
    // This will be called after ServiceLocator init
    final downloads = ServiceLocator.instance.downloadQueue.activeJobs;
    final shares = ServiceLocator.instance.webShareQueue.allShares
        .where((s) => !s.isComplete && !s.isFailed && !s.isCancelled)
        .toList();

    List<TransferTask> persistedTasks = [];

    for (final j in downloads) {
      persistedTasks.add(TransferTask(
        id: j.fileId,
        name: j.name,
        type: TransferType.download,
        sizeMb: j.sizeMb,
        progress: j.progress,
        status: j.isDownloading
            ? TransferStatus.downloading
            : TransferStatus.pending,
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
            : (j.isUploading ? TransferStatus.sharing : TransferStatus.pending),
        addedAt: j.addedAt,
      ));
    }

    _tasksNotifier.value = persistedTasks;
    _updateNotification();
  }

  void clear() {
    _tasksNotifier.value = [];
    _lastUpdateTimes.clear();
    _lastProgresses.clear();
  }
}
