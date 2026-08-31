/*
 * File: upload_view_model.dart
 * Description: Upload ViewModel (Bloc) managing queue orchestration, parallel chunked uploads, and network retries.
 */

import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mime/mime.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/models/transfer_task.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/services/transfer_queue_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/connectivity.dart';
import '../../../../core/utils/thumbnail_generator.dart';
import '../../../../core/utils/thumbnail_helper_native.dart'
    if (dart.library.js_interop) '../../../../core/utils/thumbnail_helper_web.dart';

import 'upload_task.dart';
import 'upload_event.dart';
import 'upload_state.dart';

export 'upload_task.dart';
export 'upload_event.dart';
export 'upload_state.dart';

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

  /// Flag indicating if background pre-processing loop is running.
  bool _isPreProcessing = false;

  /// Maximum concurrent upload workers.
  static const int _maxConcurrentWorkers = 3;

  /// Constructs UploadBloc and registers event handlers.
  UploadBloc() : super(UploadIdle()) {
    on<StartUpload>(_onStartUpload);
    on<AddUploads>(_onAddUploads);
    on<CancelUploadTask>(_onCancelUploadTask);
    on<ProcessNextUpload>(_onProcessNextUpload);
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

    for (final task in event.tasks) {
      final sizeMb = (task.size != null && task.size! > 0)
          ? task.size! / 1048576
          : (task.bytes != null ? task.bytes!.length / 1048576 : 0.0);
      TransferQueueService.instance.addTask(TransferTask(
        id: task.id,
        name: task.name,
        type: TransferType.upload,
        sizeMb: sizeMb,
        addedAt: DateTime.now(),
        status: TransferStatus.waiting,
        currentStage: 'Waiting in queue…',
      ));
    }

    _triggerBackgroundPreProcessing();

    // Proactively start Foreground Service and CPU wakelock in foreground context
    NotificationService.instance.startTransferSession(
      title: event.tasks.length == 1
          ? 'Uploading ${event.tasks.first.name}…'
          : 'Uploading ${event.tasks.length} files…',
      body: 'Starting upload queue',
    );

    if (!_isWaitingForNetwork) {
      final workersToSpawn =
          (_maxConcurrentWorkers - _activeWorkers).clamp(0, _queue.length);
      for (int i = 0; i < workersToSpawn; i++) {
        add(ProcessNextUpload());
      }
    }
  }

  /// Non-blocking background worker pre-generating hashes and thumbnails.
  Future<void> _triggerBackgroundPreProcessing() async {
    if (_isPreProcessing) return;
    _isPreProcessing = true;
    try {
      while (_queue.isNotEmpty && !isClosed) {
        final pending = _queue
            .cast<UploadTask?>()
            .firstWhere((t) => t != null && t.precomputedHash == null, orElse: () => null);
        if (pending == null) break;

        if (TransferQueueService.instance.isCancelled(pending.id)) {
          pending.precomputedHash = '';
          continue;
        }

        try {
          final Uint8List b = await pending.getBytes();
          pending.precomputedHash = sha256.convert(b).toString();

          final mime = lookupMimeType(pending.name) ?? 'application/octet-stream';
          final thumb = await ThumbnailGenerator.generate(
            bytes: b,
            filename: pending.name,
            mimeType: mime,
          );
          if (thumb != null) {
            pending.precomputedThumbnailBytes = thumb.bytes;
            pending.thumbnailExtension = thumb.extension;
            try {
              if (ServiceLocator.instance.isInitialized) {
                ServiceLocator.instance.thumbnailRepository
                    .addToMemoryCache(pending.id, thumb.bytes);
              }
              await ThumbnailHelper.cacheThumbnail(pending.id, thumb.bytes);
            } catch (_) {}
          }
          TransferQueueService.instance.updateTask(
            pending.id,
            currentStage: 'Ready in queue',
          );
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } finally {
      _isPreProcessing = false;
    }
  }

  /// Cancels a queued upload task before it executes.
  void _onCancelUploadTask(CancelUploadTask event, Emitter<UploadState> emit) {
    _queue.removeWhere((task) => task.id == event.taskId);
    TransferQueueService.instance.cancelTask(event.taskId);
    if (_totalCount > 0) _totalCount--;
  }

  /// Worker execution handler processing individual upload tasks.
  Future<void> _onProcessNextUpload(
      ProcessNextUpload event, Emitter<UploadState> emit) async {
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
      await NotificationService.instance.stopTransferSession();
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

    if (TransferQueueService.instance.isCancelled(task.id)) {
      await task.cleanupCacheFile();
      if (!isClosed) add(ProcessNextUpload());
      return;
    }

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

    Uint8List bytes;
    try {
      bytes = await task.getBytes();
    } catch (e) {
      AppLogger.w('Failed to read bytes for ${task.name}: $e',
          tag: 'UploadBloc');
      await task.cleanupCacheFile();
      if (!isClosed) {
        add(UploadFailed('File inaccessible: ${task.name}',
            fileName: task.name));
      }
      return;
    }

    final isBatch = _totalCount > 1;
    final result = await ServiceLocator.instance.uploadService.uploadFile(
      bytes,
      task.name,
      task.folderId,
      (progress, status) {
        if (!isClosed) {
          add(UploadProgressUpdated(
            progress,
            'Uploading ${task.name} (${_completedCount + 1}/$_totalCount)…',
          ));
        }
      },
      skipGlobalMetadataUpdate: isBatch,
      taskId: task.id,
      precomputedHash: task.precomputedHash,
      precomputedThumbnailBytes: task.precomputedThumbnailBytes,
      thumbnailExtension: task.thumbnailExtension,
    );

    switch (result) {
      case Success(:final data):
        if (isBatch && data.isNotEmpty) {
          _completedBatchMeta.add(data);
        }
        await task.cleanupCacheFile();
        if (!isClosed) add(UploadCompleted());
      case Failure(:final failure):
        if (_completedBatchMeta.isNotEmpty) {
          try {
            await ServiceLocator.instance.uploadService
                .commitUploadBatch(List.from(_completedBatchMeta));
            _completedBatchMeta.clear();
          } catch (_) {}
        }

        final isOnline = await Connectivity.hasConnection();
        final isNetworkError = !isOnline ||
            failure is NetworkFailure ||
            failure.message.contains('OfflineException') ||
            failure.message.contains('DioException') ||
            failure.message.contains('XMLHttpRequest') ||
            failure.message.contains('SocketException') ||
            failure.message.contains('Failed host lookup');

        if (isNetworkError) {
          _isWaitingForNetwork = true;
          _activeWorkers--;
          _queue.insert(0, task);
          emit(UploadWaitingForNetwork(task.name));
          _retryWhenOnline();
        } else {
          await task.cleanupCacheFile();
          if (!isClosed) {
            add(UploadFailed(failure.message, fileName: task.name));
          }
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
    if (!isClosed) add(ProcessNextUpload());
  }

  /// Marks a single upload task as failed.
  void _onUploadFailed(UploadFailed event, Emitter<UploadState> emit) {
    _completedCount++;
    _activeWorkers--;
    emit(UploadSingleError(fileName: event.fileName, message: event.message));
    if (!isClosed) add(ProcessNextUpload());
  }

  /// Clears active upload state.
  void _onResetUpload(ResetUpload event, Emitter<UploadState> emit) {
    for (final task in _queue) {
      TransferQueueService.instance.cancelTask(task.id);
    }
    _queue.clear();
    _totalCount = 0;
    _completedCount = 0;
    _activeWorkers = 0;
    _isWaitingForNetwork = false;
    NotificationService.instance.stopTransferSession();
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
          add(ProcessNextUpload());
        }
        break;
      }
    }
  }
}

/// Type alias aligning UploadBloc with MVVM nomenclature.
typedef UploadViewModel = UploadBloc;
