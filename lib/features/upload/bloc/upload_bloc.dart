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
  UploadFailed(this.message);
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
  int _completedCount = 0;
  int _totalCount = 0;
  bool _isWaitingForNetwork = false;

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

    if (state is! UploadInProgress && !_isWaitingForNetwork) {
      add(_ProcessNextUpload());
    }
  }

  void _onCancelUploadTask(CancelUploadTask event, Emitter<UploadState> emit) {
    final currentActive = _queue.isNotEmpty ? _queue.first : null;
    _queue.removeWhere((task) => task.id == event.taskId);
    if (_totalCount > 0) _totalCount--;

    if (currentActive != null && currentActive.id == event.taskId) {
      add(_ProcessNextUpload());
    }
  }

  Future<void> _onProcessNextUpload(_ProcessNextUpload event, Emitter<UploadState> emit) async {
    if (_queue.isEmpty) {
      _totalCount = 0;
      _completedCount = 0;
      _isWaitingForNetwork = false;
      emit(UploadSuccess("All files"));
      return;
    }

    if (!ServiceLocator.instance.isInitialized) {
      emit(UploadError('Not logged in'));
      return;
    }

    final task = _queue.first;

    final isOnline = await Connectivity.hasConnection();
    if (!isOnline) {
      _isWaitingForNetwork = true;
      emit(UploadWaitingForNetwork(task.name));
      _retryWhenOnline(task);
      return;
    }

    _isWaitingForNetwork = false;
    emit(UploadInProgress(
      progress: 0.0,
      status: 'Uploading ${task.name} (${_completedCount + 1}/$_totalCount)…',
      fileName: task.name,
      completedCount: _completedCount,
      totalCount: _totalCount,
    ));

    try {
      await ServiceLocator.instance.uploadService.uploadFile(
        task.bytes,
        task.name,
        task.folderId,
        (progress, status) {
          add(UploadProgressUpdated(
            progress,
            'Uploading ${task.name} (${_completedCount + 1}/$_totalCount)…',
          ));
        },
      );
      add(UploadCompleted());
    } catch (e) {
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
        emit(UploadWaitingForNetwork(task.name));
        _retryWhenOnline(task);
      } else {
        add(UploadFailed(e.toString()));
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
    if (_queue.isNotEmpty) {
      _queue.removeAt(0);
      _completedCount++;
    }
    add(_ProcessNextUpload());
  }

  void _onUploadFailed(UploadFailed event, Emitter<UploadState> emit) {
    if (_queue.isNotEmpty) {
      final failedTask = _queue.removeAt(0);
      _completedCount++;
      emit(UploadSingleError(fileName: failedTask.name, message: event.message));
    }
    add(_ProcessNextUpload());
  }

  void _onResetUpload(ResetUpload event, Emitter<UploadState> emit) {
    _queue.clear();
    _totalCount = 0;
    _completedCount = 0;
    _isWaitingForNetwork = false;
    emit(UploadIdle());
  }

  Future<void> _retryWhenOnline(UploadTask task) async {
    while (true) {
      await Future.delayed(const Duration(seconds: 5));
      if (isClosed) return;
      if (await Connectivity.hasConnection()) {
        _isWaitingForNetwork = false;
        add(_ProcessNextUpload());
        break;
      }
    }
  }
}
