/*
 * File: upload_view_model.dart
 * Description: Upload ViewModel (Bloc) managing queue orchestration, parallel chunked uploads, and network retries.
 */

import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/utils/connectivity.dart';

// ── Upload Task Definition ───────────────────────────────────────────────────

/// Immutable description of a queued upload payload.
class UploadTask {
  /// Unique task ID.
  final String id;

  /// Raw file bytes.
  final Uint8List bytes;

  /// Original file name.
  final String name;

  /// Destination folder ID.
  final String? folderId;

  /// Constructs an UploadTask.
  UploadTask({
    required this.id,
    required this.bytes,
    required this.name,
    this.folderId,
  });
}

// ── Events ────────────────────────────────────────────────────────────────────

/// Base abstract event for upload operations.
sealed class UploadEvent {}

/// Starts upload of a single file payload.
class StartUpload extends UploadEvent {
  /// File bytes.
  final Uint8List bytes;

  /// File name.
  final String name;

  /// Destination folder ID.
  final String? folderId;

  /// Constructs StartUpload event.
  StartUpload({required this.bytes, required this.name, this.folderId});
}

/// Appends a batch of UploadTasks to queue.
class AddUploads extends UploadEvent {
  /// List of upload tasks.
  final List<UploadTask> tasks;

  /// Constructs AddUploads event.
  AddUploads(this.tasks);
}

/// Cancels a queued upload task by ID.
class CancelUploadTask extends UploadEvent {
  /// Unique task identifier.
  final String taskId;

  /// Constructs CancelUploadTask event.
  CancelUploadTask(this.taskId);
}

/// Internal event triggering queue processing.
class _ProcessNextUpload extends UploadEvent {}

/// Event emitted on upload progress tick.
class UploadProgressUpdated extends UploadEvent {
  /// Progress fraction (0.0 to 1.0).
  final double progress;

  /// Progress message text.
  final String status;

  /// Constructs UploadProgressUpdated event.
  UploadProgressUpdated(this.progress, this.status);
}

/// Event emitted when an upload completes.
class UploadCompleted extends UploadEvent {}

/// Event emitted when an upload fails.
class UploadFailed extends UploadEvent {
  /// Error message description.
  final String message;

  /// Associated file name.
  final String fileName;

  /// Constructs UploadFailed event.
  UploadFailed(this.message, {required this.fileName});
}

/// Resets upload queue to idle state.
class ResetUpload extends UploadEvent {}

// ── States ────────────────────────────────────────────────────────────────────

/// Base abstract state for upload lifecycle.
sealed class UploadState {}

/// Idle state when no uploads are active.
class UploadIdle extends UploadState {}

/// State representing an active upload in progress.
class UploadInProgress extends UploadState {
  /// Current progress fraction (0.0 to 1.0).
  final double progress;

  /// Textual description of progress stage.
  final String status;

  /// Name of file currently being uploaded.
  final String fileName;

  /// Number of completed tasks in current batch.
  final int completedCount;

  /// Total number of tasks in batch.
  final int totalCount;

  /// Constructs UploadInProgress state.
  UploadInProgress({
    required this.progress,
    required this.status,
    required this.fileName,
    this.completedCount = 0,
    this.totalCount = 1,
  });
}

/// State indicating batch upload completed successfully.
class UploadSuccess extends UploadState {
  /// Summary description of uploaded file(s).
  final String fileName;

  /// Constructs UploadSuccess state.
  UploadSuccess(this.fileName);
}

/// Global upload failure state.
class UploadError extends UploadState {
  /// Error message string.
  final String message;

  /// Constructs UploadError state.
  UploadError(this.message);
}

/// State representing single file failure within a batch.
class UploadSingleError extends UploadState {
  /// File name that failed.
  final String fileName;

  /// Error message.
  final String message;

  /// Constructs UploadSingleError state.
  UploadSingleError({required this.fileName, required this.message});
}

/// State indicating upload is paused awaiting internet reconnection.
class UploadWaitingForNetwork extends UploadState {
  /// File name paused on.
  final String fileName;

  /// Constructs UploadWaitingForNetwork state.
  UploadWaitingForNetwork(this.fileName);
}

// ── ViewModel (Bloc) ──────────────────────────────────────────────────────────

/// ViewModel orchestrating background parallel chunked uploads to Telegram.
class UploadBloc extends Bloc<UploadEvent, UploadState> {
  /// In-memory queue of pending upload tasks.
  final List<UploadTask> _queue = [];

  /// Batch metadata collector for atomic commit.
  final List<Map<String, dynamic>> _completedBatchMeta = [];

  /// Count of completed uploads in current batch.
  int _completedCount = 0;

  /// Total count of uploads in current batch.
  int _totalCount = 0;

  /// Number of concurrent active workers.
  int _activeWorkers = 0;

  /// Flag indicating if queue is blocked on network connectivity.
  bool _isWaitingForNetwork = false;

  /// Maximum concurrent upload workers.
  static const int _maxConcurrentWorkers = 3;

  /// Constructs UploadBloc and registers event handlers.
  UploadBloc() : super(UploadIdle()) {
    on<StartUpload>(_onStartUpload);
    on<AddUploads>(_onAddUploads);
    on<CancelUploadTask>(_onCancelUploadTask);
    on<_ProcessNextUpload>(_onProcessNextUpload);
    on<UploadProgressUpdated>(_onUploadProgressUpdated);
    on<UploadCompleted>(_onUploadCompleted);
    on<UploadFailed>(_onUploadFailed);
    on<ResetUpload>(_onResetUpload);
  }

  /// Handles starting a single file upload.
  Future<void> _onStartUpload(
      StartUpload event, Emitter<UploadState> emit) async {
    final task = UploadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bytes: event.bytes,
      name: event.name,
      folderId: event.folderId,
    );
    add(AddUploads([task]));
  }

  /// Handles adding multiple tasks to queue.
  void _onAddUploads(AddUploads event, Emitter<UploadState> emit) {
    _queue.addAll(event.tasks);
    _totalCount += event.tasks.length;

    if (!_isWaitingForNetwork) {
      final workersToSpawn =
          (_maxConcurrentWorkers - _activeWorkers).clamp(0, _queue.length);
      for (int i = 0; i < workersToSpawn; i++) {
        add(_ProcessNextUpload());
      }
    }
  }

  /// Cancels a queued upload task before it executes.
  void _onCancelUploadTask(CancelUploadTask event, Emitter<UploadState> emit) {
    _queue.removeWhere((task) => task.id == event.taskId);
    if (_totalCount > 0) _totalCount--;
  }

  /// Worker execution handler processing individual upload tasks.
  Future<void> _onProcessNextUpload(
      _ProcessNextUpload event, Emitter<UploadState> emit) async {
    if (_queue.isEmpty && _activeWorkers == 0) {
      if (_completedBatchMeta.isNotEmpty) {
        try {
          await ServiceLocator.instance.uploadService
              .commitUploadBatch(List.from(_completedBatchMeta));
          _completedBatchMeta.clear();
        } catch (_) {}
      }
      _totalCount = 0;
      _completedCount = 0;
      _isWaitingForNetwork = false;
      emit(UploadSuccess("All files"));
      return;
    }

    if (_queue.isEmpty) return;
    if (_activeWorkers >= _maxConcurrentWorkers) return;

    if (!ServiceLocator.instance.isInitialized) {
      emit(UploadError('Not logged in'));
      return;
    }

    final task = _queue.removeAt(0);

    final isOnline = await Connectivity.hasConnection();
    if (!isOnline) {
      _queue.insert(0, task);
      _isWaitingForNetwork = true;
      emit(UploadWaitingForNetwork(task.name));
      _retryWhenOnline();
      return;
    }

    _isWaitingForNetwork = false;
    _activeWorkers++;

    emit(UploadInProgress(
      progress: 0.0,
      status: 'Uploading ${task.name} (${_completedCount + 1}/$_totalCount)…',
      fileName: task.name,
      completedCount: _completedCount,
      totalCount: _totalCount,
    ));

    try {
      final isBatch = _totalCount > 1;
      final fileMeta = await ServiceLocator.instance.uploadService.uploadFile(
        task.bytes,
        task.name,
        task.folderId,
        (progress, status) {
          add(UploadProgressUpdated(
            progress,
            'Uploading ${task.name} (${_completedCount + 1}/$_totalCount)…',
          ));
        },
        skipGlobalMetadataUpdate: isBatch,
      );

      if (isBatch && fileMeta.isNotEmpty) {
        _completedBatchMeta.add(fileMeta);
      }

      add(UploadCompleted());
    } catch (e) {
      if (_completedBatchMeta.isNotEmpty) {
        try {
          await ServiceLocator.instance.uploadService
              .commitUploadBatch(List.from(_completedBatchMeta));
          _completedBatchMeta.clear();
        } catch (_) {}
      }

      final isOnline = await Connectivity.hasConnection();
      final isNetworkError = !isOnline ||
          e is OfflineException ||
          e.toString().contains('OfflineException') ||
          e.toString().contains('DioException') ||
          e.toString().contains('XMLHttpRequest') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup');

      if (isNetworkError) {
        _isWaitingForNetwork = true;
        _activeWorkers--;
        _queue.insert(0, task);
        emit(UploadWaitingForNetwork(task.name));
        _retryWhenOnline();
      } else {
        add(UploadFailed(e.toString(), fileName: task.name));
      }
    }
  }

  /// Updates current upload progress fraction.
  void _onUploadProgressUpdated(
      UploadProgressUpdated event, Emitter<UploadState> emit) {
    final currentState = state;
    if (currentState is UploadInProgress) {
      emit(UploadInProgress(
        progress: event.progress,
        status: event.status,
        fileName: currentState.fileName,
        completedCount: currentState.completedCount,
        totalCount: currentState.totalCount,
      ));
    }
  }

  /// Marks a single upload task as completed.
  void _onUploadCompleted(UploadCompleted event, Emitter<UploadState> emit) {
    _completedCount++;
    _activeWorkers--;
    add(_ProcessNextUpload());
  }

  /// Marks a single upload task as failed.
  void _onUploadFailed(UploadFailed event, Emitter<UploadState> emit) {
    _completedCount++;
    _activeWorkers--;
    emit(UploadSingleError(fileName: event.fileName, message: event.message));
    add(_ProcessNextUpload());
  }

  /// Clears active upload state.
  void _onResetUpload(ResetUpload event, Emitter<UploadState> emit) {
    _queue.clear();
    _totalCount = 0;
    _completedCount = 0;
    _activeWorkers = 0;
    _isWaitingForNetwork = false;
    emit(UploadIdle());
  }

  /// Polling loop that resumes paused uploads upon network reconnection.
  Future<void> _retryWhenOnline() async {
    while (true) {
      await Future.delayed(const Duration(seconds: 5));
      if (isClosed) return;
      if (await Connectivity.hasConnection()) {
        _isWaitingForNetwork = false;
        for (int i = _activeWorkers;
            i < _maxConcurrentWorkers && _queue.isNotEmpty;
            i++) {
          add(_ProcessNextUpload());
        }
        break;
      }
    }
  }
}

/// Type alias aligning UploadBloc with MVVM nomenclature.
typedef UploadViewModel = UploadBloc;
