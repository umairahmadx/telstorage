/// File: home_view_model.dart
/// Description: Home screen ViewModel (Cubit) managing storage metrics, recent files, and sync status.
library;

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../core/events/domain_event_bus.dart';
import '../../../../../../core/models/app_metadata.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/models/web_share_job.dart';
import '../../../../../../core/services/service_locator.dart';
import '../../../../../../core/utils/app_logger.dart';
import '../../../../../storage/data/repositories/storage_repository.dart';

// ── States ────────────────────────────────────────────────────────────────────

/// State class holding home dashboard data, metrics, and sync status.
class HomeState {
  /// Loading state indicator flag.
  final bool isLoading;

  /// Display name of the logged-in user.
  final String? userName;

  /// Email address of the logged-in user.
  final String? userEmail;

  /// Global application metadata.
  final AppMetadata? metadata;

  /// Web share quota information map.
  final Map<String, dynamic>? webShareQuota;

  /// Total number of stored files.
  final int totalFiles;

  /// Total storage utilized in megabytes.
  final double storageUsedMb;

  /// Total web shares generated.
  final int totalShares;

  /// Total completed file downloads.
  final int totalDownloads;

  /// List of most recently accessed/uploaded files.
  final List<FileRecord> recentFiles;

  /// Current user-facing error message, if any.
  final String? errorMessage;

  /// Flag indicating if metadata synchronization is in progress.
  final bool isSyncing;

  /// Progress fraction of the ongoing sync (0.0 to 1.0).
  final double syncProgress;

  /// Textual description of current sync phase.
  final String syncStatus;

  /// Constructs a HomeState instance.
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

  /// Returns a copy of HomeState with updated fields.
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
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      isSyncing: isSyncing ?? this.isSyncing,
      syncProgress: syncProgress ?? this.syncProgress,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}

// ── ViewModel (Cubit) ─────────────────────────────────────────────────────────

/// ViewModel handling Home dashboard business logic and real-time updates.
class HomeCubit extends Cubit<HomeState> {
  /// Internal reference to storage repository.
  final StorageRepository _repository =
      ServiceLocator.instance.storageRepository;

  /// Subscription to local Hive files box.
  StreamSubscription? _filesSubscription;

  /// Subscription to local Hive folders box.
  StreamSubscription? _foldersSubscription;

  /// Subscription to global domain event bus.
  StreamSubscription? _domainEventSubscription;

  /// Flag indicating if database listeners have been initialized.
  bool _isSubscribed = false;

  /// Constructs HomeCubit and binds event bus listener.
  HomeCubit() : super(HomeState()) {
    _domainEventSubscription = DomainEventBus.instance.stream.listen((_) {
      if (!isClosed) refreshData();
    });
  }

  /// Sets up reactive Hive database listeners.
  void _initSubscriptions() {
    if (_isSubscribed) return;
    try {
      _filesSubscription = ServiceLocator.instance.hive.filesListenable.value
          .watch()
          .listen((_) {
        if (!isClosed) {
          refreshData();
        }
      });
      _foldersSubscription = ServiceLocator
          .instance.hive.foldersListenable.value
          .watch()
          .listen((_) {
        if (!isClosed) {
          refreshData();
        }
      });
      _isSubscribed = true;
    } catch (e) {
      AppLogger.w('Could not initialize HomeCubit subscriptions: $e',
          tag: 'HomeCubit');
    }
  }

  /// Initializes home state and starts auto-sync.
  Future<void> initialize() async {
    emit(state.copyWith(isLoading: true));
    try {
      await ServiceLocator.instance.init();
      _initSubscriptions();
      await refreshData();
      sync();
    } catch (e) {
      emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
    }
  }

  /// Refreshes user metrics, recent files, and quota stats.
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
    } catch (_) {}

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

  /// Triggers cloud metadata synchronization with Telegram backend.
  Future<void> sync() async {
    if (state.isSyncing) return;

    emit(state.copyWith(
        isSyncing: true, syncProgress: 0.0, syncStatus: 'Connecting...'));

    try {
      await ServiceLocator.instance.syncService.syncFromTelegram(
        onProgress: (progress, status) {
          if (!isClosed) {
            emit(state.copyWith(syncProgress: progress, syncStatus: status));
          }
        },
      );

      await refreshData();
      emit(state.copyWith(isSyncing: false, syncStatus: 'Sync complete'));
    } catch (e) {
      AppLogger.e('HomeCubit: sync failed', tag: 'HomeCubit', error: e);
      emit(state.copyWith(isSyncing: false, errorMessage: 'Sync failed: $e'));
    }
  }

  /// Enqueues a file download task.
  Future<void> downloadFile(FileRecord file) async {
    try {
      await _repository.enqueueDownload(file);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to start download: $e'));
    }
  }

  /// Enqueues a web share link generation task.
  Future<void> shareFile(FileRecord file,
      {String? password, int? expiryDays, String? vanitySlug}) async {
    try {
      await _repository.enqueueWebShare(file,
          password: password,
          expiryDays: expiryDays,
          vanitySlug: vanitySlug);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to start sharing: $e'));
    }
  }

  /// Retrieves an existing web share job by file ID.
  WebShareJob? getShareJob(String fileId) {
    return _repository.getWebShareJob(fileId);
  }

  /// Resets state to default.
  void reset() => emit(HomeState());

  @override
  Future<void> close() {
    _filesSubscription?.cancel();
    _foldersSubscription?.cancel();
    _domainEventSubscription?.cancel();
    return super.close();
  }
}

/// Type alias aligning HomeCubit with MVVM nomenclature.
typedef HomeViewModel = HomeCubit;
