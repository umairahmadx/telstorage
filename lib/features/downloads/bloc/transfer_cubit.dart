import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/download_job.dart';
import '../../../core/models/web_share_job.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/transfer_task.dart';
import '../../../core/services/service_locator.dart';

// ── States ────────────────────────────────────────────────────────────────────

class TransferState {
  final bool isLoading;
  final bool isInitialized;
  final List<DownloadJob> downloadJobs;
  final List<FileRecord> uploadJobs; // We use FileRecord as upload history for now
  final List<WebShareJob> shareJobs;
  final List<TransferTask> activeTasks;
  final String? errorMessage;

  TransferState({
    this.isLoading = false,
    this.isInitialized = false,
    this.downloadJobs = const [],
    this.uploadJobs = const [],
    this.shareJobs = const [],
    this.activeTasks = const [],
    this.errorMessage,
  });

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
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class TransferCubit extends Cubit<TransferState> {
  TransferCubit() : super(TransferState());

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

  void _initSubscriptions() {
    ServiceLocator.instance.transferQueue.tasksNotifier.addListener(_onTasksChanged);
    ServiceLocator.instance.downloadQueue.listenable.addListener(_onDownloadsChanged);
    ServiceLocator.instance.webShareQueue.listenable.addListener(_onSharesChanged);
    ServiceLocator.instance.hive.filesListenable.addListener(_onFilesChanged);
  }

  void _onTasksChanged() {
    if (!isClosed) {
      emit(state.copyWith(activeTasks: ServiceLocator.instance.transferQueue.tasks));
    }
  }

  void _onDownloadsChanged() {
    if (!isClosed) {
      emit(state.copyWith(downloadJobs: ServiceLocator.instance.downloadQueue.allJobs));
    }
  }

  void _onSharesChanged() {
    if (!isClosed) {
      emit(state.copyWith(shareJobs: ServiceLocator.instance.webShareQueue.allShares));
    }
  }

  void _onFilesChanged() {
    if (!isClosed) {
      emit(state.copyWith(uploadJobs: ServiceLocator.instance.hive.allFiles));
    }
  }

  void _refreshAll() {
    emit(state.copyWith(
      activeTasks: ServiceLocator.instance.transferQueue.tasks,
      downloadJobs: ServiceLocator.instance.downloadQueue.allJobs,
      shareJobs: ServiceLocator.instance.webShareQueue.allShares,
      uploadJobs: ServiceLocator.instance.hive.allFiles,
    ));
  }

  Future<void> enqueueDownload(FileRecord file) async {
    try {
      await ServiceLocator.instance.storageRepository.enqueueDownload(file);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> enqueueShare(FileRecord file, {String? password, int? expiryDays}) async {
    try {
      await ServiceLocator.instance.storageRepository.enqueueWebShare(file, 
          password: password, expiryDays: expiryDays);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  FileRecord? getFile(String fileId) {
    return ServiceLocator.instance.storageRepository.getFile(fileId);
  }

  WebShareJob? getShareJob(String fileId) {
    return ServiceLocator.instance.storageRepository.getWebShareJob(fileId);
  }

  Future<void> deleteShareJob(String fileId) async {
    try {
      await ServiceLocator.instance.webShareQueue.deleteShare(fileId);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  Future<void> deleteDownloadedFile(String fileId) async {
    try {
      await ServiceLocator.instance.downloadQueue.deleteJobAndLocalFile(fileId);
    } catch (e) {
      emit(state.copyWith(errorMessage: e.toString()));
    }
  }

  @override
  Future<void> close() {
    ServiceLocator.instance.transferQueue.tasksNotifier.removeListener(_onTasksChanged);
    ServiceLocator.instance.downloadQueue.listenable.removeListener(_onDownloadsChanged);
    ServiceLocator.instance.webShareQueue.listenable.removeListener(_onSharesChanged);
    ServiceLocator.instance.hive.filesListenable.removeListener(_onFilesChanged);
    return super.close();
  }
}
