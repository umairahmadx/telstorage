import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/connectivity.dart';

// ── Upload Task Definition ───────────────────────────────────────────────────

class UploadTask {
  final String id;
  final Uint8List bytes;
  final String name;
  final String? folderId;

  UploadTask({
    required this.id,
    required this.bytes,
    required this.name,
    this.folderId,
  });
}

// ── Events ────────────────────────────────────────────────────────────────────

sealed class UploadEvent {}

class StartUpload extends UploadEvent {
  final Uint8List bytes;
  final String name;
  final String? folderId;
  StartUpload({required this.bytes, required this.name, this.folderId});
}

class AddUploads extends UploadEvent {
  final List<UploadTask> tasks;
  AddUploads(this.tasks);
}

class CancelUploadTask extends UploadEvent {
  final String taskId;
  CancelUploadTask(this.taskId);
}

class _ProcessNextUpload extends UploadEvent {}

class UploadProgressUpdated extends UploadEvent {
  final double progress;
  final String status;
  UploadProgressUpdated(this.progress, this.status);
}

class UploadCompleted extends UploadEvent {}

class UploadFailed extends UploadEvent {
  final String message;
  final String fileName;
  UploadFailed(this.message, {required this.fileName});
}

class ResetUpload extends UploadEvent {}

// ── States ────────────────────────────────────────────────────────────────────

sealed class UploadState {}

class UploadIdle extends UploadState {}

class UploadInProgress extends UploadState {
  final double progress;
  final String status;
  final String fileName;
  final int completedCount;
  final int totalCount;

  UploadInProgress({
    required this.progress,
    required this.status,
    required this.fileName,
    this.completedCount = 0,
    this.totalCount = 1,
  });
}

class UploadSuccess extends UploadState {
  final String fileName;
  UploadSuccess(this.fileName);
}

class UploadError extends UploadState {
  final String message;
  UploadError(this.message);
}

class UploadSingleError extends UploadState {
  final String fileName;
  final String message;
  UploadSingleError({required this.fileName, required this.message});
}

class UploadWaitingForNetwork extends UploadState {
  final String fileName;
  UploadWaitingForNetwork(this.fileName);
}

// ── BLoC ──────────────────────────────────────────────────────────────────────

class UploadBloc extends Bloc<UploadEvent, UploadState> {
  final List<UploadTask> _queue = [];
  final List<Map<String, dynamic>> _completedBatchMeta = [];
  int _completedCount = 0;
  int _totalCount = 0;
  int _activeWorkers = 0;
  bool _isWaitingForNetwork = false;

  static const int _maxConcurrentWorkers = 3;

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

  Future<void> _onStartUpload(StartUpload event, Emitter<UploadState> emit) async {
    final task = UploadTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bytes: event.bytes,
      name: event.name,
      folderId: event.folderId,
    );
    add(AddUploads([task]));
  }

  void _onAddUploads(AddUploads event, Emitter<UploadState> emit) {
    _queue.addAll(event.tasks);
    _totalCount += event.tasks.length;

    // Spawn workers up to the concurrency cap
    if (!_isWaitingForNetwork) {
      final workersToSpawn = (_maxConcurrentWorkers - _activeWorkers).clamp(0, _queue.length);
      for (int i = 0; i < workersToSpawn; i++) {
        add(_ProcessNextUpload());
      }
    }
  }

  void _onCancelUploadTask(CancelUploadTask event, Emitter<UploadState> emit) {
    _queue.removeWhere((task) => task.id == event.taskId);
    if (_totalCount > 0) _totalCount--;
  }

  Future<void> _onProcessNextUpload(_ProcessNextUpload event, Emitter<UploadState> emit) async {
    // All work done — commit batch and reset
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

    // No more queued items but workers still active — wait for them
    if (_queue.isEmpty) return;

    // Concurrency cap reached — this worker must wait
    if (_activeWorkers >= _maxConcurrentWorkers) return;

    if (!ServiceLocator.instance.isInitialized) {
      emit(UploadError('Not logged in'));
      return;
    }

    final task = _queue.removeAt(0);

    final isOnline = await Connectivity.hasConnection();
    if (!isOnline) {
      _queue.insert(0, task); // Put it back
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
      // Flush successful batch items before reporting failure
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
        _queue.insert(0, task); // Re-queue for retry
        emit(UploadWaitingForNetwork(task.name));
        _retryWhenOnline();
      } else {
        add(UploadFailed(e.toString(), fileName: task.name));
      }
    }
  }

  void _onUploadProgressUpdated(UploadProgressUpdated event, Emitter<UploadState> emit) {
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

  void _onUploadCompleted(UploadCompleted event, Emitter<UploadState> emit) {
    _completedCount++;
    _activeWorkers--;
    // Dispatch next worker — may spawn additional parallel workers too
    add(_ProcessNextUpload());
  }

  void _onUploadFailed(UploadFailed event, Emitter<UploadState> emit) {
    _completedCount++;
    _activeWorkers--;
    emit(UploadSingleError(fileName: event.fileName, message: event.message));
    // Continue processing remaining queue
    add(_ProcessNextUpload());
  }

  void _onResetUpload(ResetUpload event, Emitter<UploadState> emit) {
    _queue.clear();
    _totalCount = 0;
    _completedCount = 0;
    _activeWorkers = 0;
    _isWaitingForNetwork = false;
    emit(UploadIdle());
  }

  Future<void> _retryWhenOnline() async {
    while (true) {
      await Future.delayed(const Duration(seconds: 5));
      if (isClosed) return;
      if (await Connectivity.hasConnection()) {
        _isWaitingForNetwork = false;
        // Re-spawn workers up to the cap
        for (int i = _activeWorkers; i < _maxConcurrentWorkers && _queue.isNotEmpty; i++) {
          add(_ProcessNextUpload());
        }
        break;
      }
    }
  }
}

