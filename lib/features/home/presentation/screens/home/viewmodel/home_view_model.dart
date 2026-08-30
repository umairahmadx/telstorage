/*
 * File: home_view_model.dart
 * Description: Home screen ViewModel (Cubit) managing storage metrics, recent files, and sync status.
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
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

  /// Debounce timer for coalescing rapid local database updates.
  Timer? _debounceTimer;

  /// Flag indicating if database listeners have been initialized.
  bool _isSubscribed = false;

  /// Monotonically increasing counter for local cache refreshes.
  int _localRefreshRequestId = 0;

  /// Monotonically increasing counter for remote network enrichments.
  int _enrichRequestId = 0;

  /// Timestamp of the last remote enrichment to prevent duplicate in-flight requests.
  DateTime? _lastEnrichTime;

  /// Constructs HomeCubit and binds event bus listener.
  HomeCubit() : super(HomeState()) {
    _domainEventSubscription = DomainEventBus.instance.stream.listen((_) {
      _scheduleDebouncedLocalRefresh();
    });
  }

  /// Sets up reactive Hive database listeners with debouncing.
  void _initSubscriptions() {
    if (_isSubscribed) return;
    try {
      _filesSubscription = ServiceLocator.instance.hive.filesListenable.value
          .watch()
          .listen((_) => _scheduleDebouncedLocalRefresh());
      _foldersSubscription = ServiceLocator
          .instance.hive.foldersListenable.value
          .watch()
          .listen((_) => _scheduleDebouncedLocalRefresh());
      _isSubscribed = true;
    } catch (e) {
      AppLogger.w('Could not initialize HomeCubit subscriptions: $e',
          tag: 'HomeCubit', error: e);
    }
  }

  /// Coalesces rapid local Hive change events (e.g. bulk uploads / sync).
  /// Note: Only recalculates local metrics and NEVER touches the network.
  void _scheduleDebouncedLocalRefresh() {
    if (isClosed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!isClosed) {
        refreshLocalData();
      }
    });
  }

  /// Testing hook to invoke debounced refresh.
  @visibleForTesting
  void scheduleDebouncedLocalRefreshForTesting() =>
      _scheduleDebouncedLocalRefresh();

  /// Initializes home state with local cache immediately and starts auto-sync.
  Future<void> initialize() async {
    try {
      if (!ServiceLocator.instance.isInitialized) {
        await ServiceLocator.instance.init();
      }
      _initSubscriptions();
      await refreshLocalData();
      unawaited(enrichRemoteData());
      unawaited(sync(userInitiated: false));
    } catch (e, stack) {
      AppLogger.e('HomeCubit initialization failed: $e',
          tag: 'HomeCubit', error: e, stackTrace: stack);
      if (!isClosed) {
        emit(state.copyWith(isLoading: false, errorMessage: e.toString()));
      }
    }
  }

  /// Phase 1: Pure 0ms Local Hive Cache Read (no network calls).
  Future<void> refreshLocalData() async {
    final requestId = ++_localRefreshRequestId;

    try {
      final email = await _repository.getUserEmail();
      final recent = _repository.getRecentFiles(5);
      final totalFiles = _repository.getTotalFiles();
      final usedMb = _repository.getTotalSizeMb();
      final totalShares = _repository.getTotalShares();
      final totalDownloads = _repository.getTotalCompletedDownloads();

      String? name;
      if (email != null) {
        name = email.split('@').first;
        if (name.isNotEmpty) {
          name = name[0].toUpperCase() + name.substring(1);
        }
      }

      if (isClosed || requestId != _localRefreshRequestId) return;

      emit(state.copyWith(
        isLoading: false,
        userName: name ?? state.userName,
        userEmail: email ?? state.userEmail,
        recentFiles: recent,
        totalFiles: totalFiles,
        storageUsedMb: usedMb,
        totalShares: totalShares,
        totalDownloads: totalDownloads,
      ));
    } catch (e) {
      AppLogger.w('Local data read error in HomeCubit: $e',
          tag: 'HomeCubit', error: e);
    }
  }

  /// Phase 2: Parallel Remote Network Enrichment with content equality check and cooldown lock.
  Future<void> enrichRemoteData({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastEnrichTime != null &&
        now.difference(_lastEnrichTime!).inSeconds < 5) {
      return;
    }

    // Claim slot immediately at invocation start to guard concurrent in-flight calls
    _lastEnrichTime = now;
    final requestId = ++_enrichRequestId;

    try {
      final (quota, meta) = await (
        () async {
          try {
            return await _repository.getWebShareQuota();
          } catch (e) {
            AppLogger.w('Failed to fetch web share quota: $e',
                tag: 'HomeCubit', error: e);
            return null;
          }
        }(),
        () async {
          try {
            return await _repository.getAppMetadata();
          } catch (e) {
            AppLogger.w('Failed to fetch app metadata: $e',
                tag: 'HomeCubit', error: e);
            return null;
          }
        }(),
      ).wait;

      if (isClosed || requestId != _enrichRequestId) return;

      // Content equality deduplication
      final isQuotaUnchanged =
          quota == null || mapEquals(quota, state.webShareQuota);
      final isMetaUnchanged =
          meta == null || mapEquals(meta.toJson(), state.metadata?.toJson());

      if (isQuotaUnchanged && isMetaUnchanged) return;

      emit(state.copyWith(
        webShareQuota: quota ?? state.webShareQuota,
        metadata: meta ?? state.metadata,
      ));
    } catch (e) {
      AppLogger.w('Background enrichment error in HomeCubit: $e',
          tag: 'HomeCubit', error: e);
    }
  }

  /// Backward-compatible unified refresh method for existing callers and tests.
  Future<void> refreshData() async {
    await refreshLocalData();
    await enrichRemoteData(force: true);
  }

  /// Triggers cloud metadata synchronization with Telegram backend.
  Future<void> sync({bool userInitiated = false}) async {
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

      await refreshLocalData();
      unawaited(enrichRemoteData(force: userInitiated));
      emit(state.copyWith(isSyncing: false, syncStatus: 'Sync complete'));
    } catch (e, stack) {
      AppLogger.e('HomeCubit: sync failed',
          tag: 'HomeCubit', error: e, stackTrace: stack);
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
          password: password, expiryDays: expiryDays, vanitySlug: vanitySlug);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to start sharing: $e'));
    }
  }

  /// Retrieves an existing web share job by file ID.
  WebShareJob? getShareJob(String fileId) {
    return _repository.getWebShareJob(fileId);
  }

  /// Renames a file by ID.
  Future<void> renameFile(String fileId, String newName) async {
    try {
      await _repository.renameFile(fileId, newName);
      await refreshLocalData();
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to rename file: $e'));
    }
  }

  /// Deletes a file by ID.
  Future<void> deleteFile(String fileId) async {
    try {
      await _repository.deleteFile(fileId);
      await refreshLocalData();
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Failed to delete file: $e'));
    }
  }

  /// Resets state to default.
  void reset() => emit(HomeState());

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    _filesSubscription?.cancel();
    _foldersSubscription?.cancel();
    _domainEventSubscription?.cancel();
    return super.close();
  }
}

/// Type alias aligning HomeCubit with MVVM nomenclature.
typedef HomeViewModel = HomeCubit;
