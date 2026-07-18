import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/app_metadata.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/web_share_job.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/app_logger.dart';
import '../../storage/data/repositories/storage_repository.dart';

// ── States ────────────────────────────────────────────────────────────────────

class HomeState {
  final bool isLoading;
  final String? userName;
  final String? userEmail;
  final AppMetadata? metadata;
  final Map<String, dynamic>? webShareQuota;
  final int totalFiles;
  final double storageUsedMb;
  final int totalShares;
  final int totalDownloads;
  final List<FileRecord> recentFiles;
  final String? errorMessage;
  
  // Sync Status
  final bool isSyncing;
  final double syncProgress;
  final String syncStatus;

  HomeState({
    this.isLoading = false,
    this.userName,
    this.userEmail,
    this.metadata,
    this.webShareQuota,
    this.totalFiles = 0,
    this.storageUsedMb = 0,
    this.totalShares = 0,
    this.totalDownloads = 0,
    this.recentFiles = const [],
    this.errorMessage,
    this.isSyncing = false,
    this.syncProgress = 0.0,
    this.syncStatus = '',
  });

  HomeState copyWith({
    bool? isLoading,
    String? userName,
    String? userEmail,
    AppMetadata? metadata,
    Map<String, dynamic>? webShareQuota,
    int? totalFiles,
    double? storageUsedMb,
    int? totalShares,
    int? totalDownloads,
    List<FileRecord>? recentFiles,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? isSyncing,
    double? syncProgress,
    String? syncStatus,
  }) {
    return HomeState(
      isLoading: isLoading ?? this.isLoading,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      metadata: metadata ?? this.metadata,
      webShareQuota: webShareQuota ?? this.webShareQuota,
      totalFiles: totalFiles ?? this.totalFiles,
      storageUsedMb: storageUsedMb ?? this.storageUsedMb,
      totalShares: totalShares ?? this.totalShares,
      totalDownloads: totalDownloads ?? this.totalDownloads,
      recentFiles: recentFiles ?? this.recentFiles,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isSyncing: isSyncing ?? this.isSyncing,
      syncProgress: syncProgress ?? this.syncProgress,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class HomeCubit extends Cubit<HomeState> {
  final StorageRepository _repository = ServiceLocator.instance.storageRepository;
  
  HomeCubit() : super(HomeState());

  Future<void> initialize() async {
    emit(state.copyWith(isLoading: true));
    try {
      await ServiceLocator.instance.init();
      await refreshData();
      
      // Auto-sync on start
      sync();
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  Future<void> refreshData() async {
    final email = await _repository.getUserEmail();
    final recent = _repository.getRecentFiles(5);
    final totalFiles = _repository.getTotalFiles();
    final usedMb = _repository.getTotalSizeMb();
    final totalShares = _repository.getTotalShares();
    final totalDownloads = _repository.getTotalCompletedDownloads();
    
    Map<String, dynamic>? quota;
    try {
      quota = await _repository.getWebShareQuota();
    } catch (_) {}

    String? name;
    if (email != null) {
      name = email.split('@').first;
      if (name.isNotEmpty) {
        name = name[0].toUpperCase() + name.substring(1);
      }
    }

    AppMetadata? meta;
    try {
      meta = await _repository.getAppMetadata();
    } catch (_) {
      // Offline or first time
    }

    emit(state.copyWith(
      isLoading: false,
      userName: name,
      userEmail: email,
      recentFiles: recent,
      totalFiles: totalFiles,
      storageUsedMb: usedMb,
      totalShares: totalShares,
      totalDownloads: totalDownloads,
      metadata: meta,
      webShareQuota: quota,
    ));
  }

  Future<void> sync() async {
    if (state.isSyncing) return;
    
    emit(state.copyWith(isSyncing: true, syncProgress: 0.0, syncStatus: 'Connecting...'));
    
    try {
      await ServiceLocator.instance.syncService.syncFromTelegram(
        onProgress: (progress, status) {
          if (!isClosed) {
            emit(state.copyWith(syncProgress: progress, syncStatus: status));
          }
        },
      );
      
      // Refresh local data after sync
      await refreshData();
      
      emit(state.copyWith(isSyncing: false, syncStatus: 'Sync complete'));
    } catch (e) {
      AppLogger.e('HomeCubit: sync failed', tag: 'HomeCubit', error: e);
      emit(state.copyWith(isSyncing: false, errorMessage: 'Sync failed: $e'));
    }
  }

  Future<void> downloadFile(FileRecord file) async {
    try {
      await _repository.enqueueDownload(file);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to start download: $e'));
    }
  }

  Future<void> shareFile(FileRecord file, {String? password, int? expiryDays}) async {
    try {
      await _repository.enqueueWebShare(file, password: password, expiryDays: expiryDays);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to start sharing: $e'));
    }
  }

  WebShareJob? getShareJob(String fileId) {
    return _repository.getWebShareJob(fileId);
  }

  void reset() => emit(HomeState());
}
