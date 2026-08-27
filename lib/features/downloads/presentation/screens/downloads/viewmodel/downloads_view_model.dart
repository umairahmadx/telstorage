/*
 * File: downloads_view_model.dart
 * Description: Downloads and transfers ViewModel (Cubit) tracking active, completed, and shared file tasks.
 */

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../core/models/download_job.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/models/transfer_task.dart';
import '../../../../../../core/models/web_share_job.dart';
import '../../../../../../core/services/service_locator.dart';
import '../../../../../storage/domain/usecases/generate_web_share_usecase.dart';

// ── States ────────────────────────────────────────────────────────────────────

/// State holding active transfer tasks, download jobs, shares, and upload histories.
class TransferState {
  /// Loading state indicator.
  final bool isLoading;

  /// Flag indicating if data has been fetched from storage queues.
  final bool isInitialized;

  /// List of historical/active download jobs.
  final List<DownloadJob> downloadJobs;

  /// List of uploaded file records.
  final List<FileRecord> uploadJobs;

  /// List of active web share jobs.
  final List<WebShareJob> shareJobs;

  /// Real-time active download and upload transfer tasks.
  final List<TransferTask> activeTasks;

  /// Error message, if an operation failed.
  final String? errorMessage;

  /// Constructs a TransferState instance.
  TransferState({
    this.isLoading = false,
    this.isInitialized = false,
    this.downloadJobs = const [],
    this.uploadJobs = const [],
    this.shareJobs = const [],
    this.activeTasks = const [],
    this.errorMessage,
  });

  /// Returns a copy of TransferState with updated fields.
  TransferState copyWith({
    bool? isLoading,
    bool? isInitialized,
    List<DownloadJob>? downloadJobs,
    List<FileRecord>? uploadJobs,
    List<WebShareJob>? shareJobs,
    List<TransferTask>? activeTasks,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return TransferState(
      isLoading: isLoading ?? this.isLoading,
      isInitialized: isInitialized ?? this.isInitialized,
      downloadJobs: downloadJobs ?? this.downloadJobs,
      uploadJobs: uploadJobs ?? this.uploadJobs,
      shareJobs: shareJobs ?? this.shareJobs,
      activeTasks: activeTasks ?? this.activeTasks,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ── ViewModel (Cubit) ─────────────────────────────────────────────────────────

/// ViewModel managing file downloads, active transfers, and link shares.
class TransferCubit extends Cubit<TransferState> {
  /// Flag preventing duplicate listener subscriptions.
  bool _isSubscribed = false;

  /// Constructs TransferCubit with default state.
  TransferCubit() : super(TransferState());

  /// Initializes transfer subscriptions and loads initial records.
  Future<void> initialize() async {
    emit(state.copyWith(isLoading: true));
    try {
      if (!ServiceLocator.instance.isInitialized) {
        await ServiceLocator.instance.init();
      }

      _refreshAll();
      _initSubscriptions();

      emit(state.copyWith(isLoading: false, isInitialized: true));
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  /// Sets up listeners to active transfer queues and databases.
  void _initSubscriptions() {
    if (_isSubscribed) return;
    _isSubscribed = true;
    ServiceLocator.instance.transferQueue.tasksNotifier
        .addListener(_onTasksChanged);
    ServiceLocator.instance.downloadQueue.listenable
        .addListener(_onDownloadsChanged);
    ServiceLocator.instance.webShareQueue.listenable
        .addListener(_onSharesChanged);
    ServiceLocator.instance.hive.filesListenable.addListener(_onFilesChanged);
  }

  /// Listener for active transfer progress updates.
  void _onTasksChanged() {
    if (!isClosed) {
      emit(state.copyWith(
          activeTasks: ServiceLocator.instance.transferQueue.activeTasks));
    }
  }

  /// Listener for download queue job changes.
  void _onDownloadsChanged() {
    if (!isClosed) {
      emit(state.copyWith(
          downloadJobs: ServiceLocator.instance.downloadQueue.allJobs));
    }
  }

  /// Listener for web share queue job changes.
  void _onSharesChanged() {
    if (!isClosed) {
      emit(state.copyWith(
          shareJobs: ServiceLocator.instance.webShareQueue.allShares));
    }
  }

  /// Listener for local files database updates.
  void _onFilesChanged() {
    if (!isClosed) {
      emit(state.copyWith(uploadJobs: ServiceLocator.instance.hive.allFiles));
    }
  }

  /// Refreshes all transfer state properties from their respective services.
  void _refreshAll() {
    emit(state.copyWith(
      activeTasks: ServiceLocator.instance.transferQueue.activeTasks,
      downloadJobs: ServiceLocator.instance.downloadQueue.allJobs,
      shareJobs: ServiceLocator.instance.webShareQueue.allShares,
      uploadJobs: ServiceLocator.instance.hive.allFiles,
    ));
  }

  /// Enqueues download for a specific file.
  Future<void> enqueueDownload(FileRecord file) async {
    final result = await ServiceLocator.instance.downloadFileUseCase(file);
    result.fold(
      (_) {},
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
    );
  }

  /// Enqueues web share link creation.
  Future<void> enqueueShare(FileRecord file,
      {String? password, int? expiryDays, String? vanitySlug}) async {
    final result = await ServiceLocator.instance.generateWebShareUseCase(
      GenerateWebShareParams(
        file: file,
        password: password,
        expiryDays: expiryDays,
        vanitySlug: vanitySlug,
      ),
    );
    result.fold(
      (_) {},
      (failure) => emit(state.copyWith(errorMessage: failure.message)),
    );
  }

  /// Retrieves FileRecord by its file ID.
  FileRecord? getFile(String fileId) {
    return ServiceLocator.instance.storageRepository.getFile(fileId);
  }

  /// Retrieves WebShareJob by file ID.
  WebShareJob? getShareJob(String fileId) {
    return ServiceLocator.instance.storageRepository.getWebShareJob(fileId);
  }

  /// Deletes a web share by file ID.
  Future<void> deleteShareJob(String fileId) async {
    try {
      await ServiceLocator.instance.webShareQueue.deleteShare(fileId);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  /// Deletes downloaded file on device storage and clears queue record.
  Future<void> deleteDownloadedFile(String fileId) async {
    try {
      await ServiceLocator.instance.downloadQueue.deleteJobAndLocalFile(fileId);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  /// Clears all completed download records from local queue.
  Future<void> clearCompletedDownloads() async {
    try {
      await ServiceLocator.instance.downloadQueue.clearCompleted();
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  @override
  Future<void> close() {
    if (_isSubscribed) {
      ServiceLocator.instance.transferQueue.tasksNotifier
          .removeListener(_onTasksChanged);
      ServiceLocator.instance.downloadQueue.listenable
          .removeListener(_onDownloadsChanged);
      ServiceLocator.instance.webShareQueue.listenable
          .removeListener(_onSharesChanged);
      ServiceLocator.instance.hive.filesListenable
          .removeListener(_onFilesChanged);
    }
    return super.close();
  }
}

/// Type alias aligning TransferCubit with MVVM nomenclature.
typedef DownloadsViewModel = TransferCubit;
