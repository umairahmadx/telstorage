/*
 * File: service_locator.dart
 * Description: Component and logic definition for service_locator.dart in TelStorage.
 */

import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import '../utils/app_logger.dart';
import 'download_queue_service.dart';
import 'download_service.dart';
import 'notification_service.dart';
import 'file_manager.dart';
import 'hive_service.dart';
import 'metadata_service.dart';
import 'sync_service.dart';
import 'telegram_service.dart';
import 'upload_service.dart';
import 'web_share_queue_service.dart';
import 'sync_queue_service.dart';
import 'thumbnail_repository.dart';
import 'navigation_service.dart';
import 'transfer_queue_service.dart';
import 'app_cache_manager.dart';
import 'lru_folder_cache_service.dart';
import 'telegram_rate_limiter.dart';
import '../../features/storage/data/repositories/storage_repository.dart';
import 'upload_service_contract.dart';
import 'download_service_contract.dart';
import '../../features/storage/domain/repositories/storage_repository_contract.dart';
import '../../features/storage/domain/usecases/download_file_usecase.dart';
import '../../features/storage/domain/usecases/generate_web_share_usecase.dart';

/// Single initialization point for all services.
/// Call [ServiceLocator.instance.init()] after login.
/// Call [ServiceLocator.instance.reset()] on logout.
///
/// Eliminates the double-init bug where HomeScreen and BrowserScreen
/// each created fresh service instances on every page visit.
class ServiceLocator {
  ServiceLocator._();
  static final ServiceLocator instance = ServiceLocator._();

  // ── State ────────────────────────────────────────────────────────────────
  bool _initialized = false;
  bool get isInitialized => _initialized;

  // ── Services (null until init() is called) ───────────────────────────────
  late TelegramService _telegram;
  late HiveService _hive;
  late MetadataService _metadata;
  late SyncService _syncService;
  late UploadService _uploadService;
  late DownloadService _downloadService;
  late DownloadQueueService _downloadQueue;
  late FileManagerService _fileManager;
  late SyncQueueService _syncQueue;
  late StorageRepository _storageRepository;
  late ThumbnailRepository _thumbnailRepository;
  late WebShareQueueService _webShareQueue;
  late DownloadFileUseCase _downloadFileUseCase;
  late GenerateWebShareUseCase _generateWebShareUseCase;

  // These are always available as they don't depend on user credentials for creation
  final NavigationService _navigation = NavigationService.instance;
  final TransferQueueService _transferQueue = TransferQueueService.instance;
  final AppCacheManager _cacheManager = AppCacheManager.instance;

  TelegramService get telegram => _telegram;
  HiveService get hive => _hive;
  MetadataService get metadata => _metadata;
  SyncService get syncService => _syncService;

  UploadServiceContract get uploadServiceContract => _uploadService;
  DownloadServiceContract get downloadServiceContract => _downloadService;
  StorageRepositoryContract get storageRepositoryContract => _storageRepository;
  UploadService get uploadService => _uploadService;
  DownloadService get downloadService => _downloadService;
  DownloadQueueService get downloadQueue => _downloadQueue;
  FileManagerService get fileManager => _fileManager;
  SyncQueueService get syncQueue => _syncQueue;
  StorageRepository get storageRepository => _storageRepository;
  ThumbnailRepository get thumbnailRepository => _thumbnailRepository;
  WebShareQueueService get webShareQueue => _webShareQueue;
  DownloadFileUseCase get downloadFileUseCase => _downloadFileUseCase;
  GenerateWebShareUseCase get generateWebShareUseCase => _generateWebShareUseCase;
  NavigationService get navigation => _navigation;
  TransferQueueService get transferQueue => _transferQueue;
  AppCacheManager get cacheManager => _cacheManager;

  Future<void>? _initFuture;

  // ── Init ─────────────────────────────────────────────────────────────────

  /// Initialize all services with the user's credentials.
  /// Safe to call multiple times — subsequent calls are no-ops if already initialized.
  Future<void> init() {
    _initFuture ??= _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    AppLogger.i('Initializing ServiceLocator...', tag: 'ServiceLocator');

    const storage = FlutterSecureStorage();

    final token = await storage.read(key: AppConstants.keyBotToken);
    final channelId = await storage.read(key: AppConstants.keyChannelId);

    if (token == null || channelId == null) {
      _initFuture = null;
      throw Exception(
          'Bot credentials not found in secure storage. Please log in again.');
    }

    try {
      _telegram = TelegramService();
      await _telegram.init(token, channelId);

      _hive = HiveService.instance;

      _metadata = MetadataService(_telegram);
      _syncService = SyncService(_metadata, _hive);
      _uploadService = UploadService(_telegram, _metadata, _hive);
      _downloadService = DownloadService(_telegram);
      _downloadQueue =
          DownloadQueueService(_downloadService, AppConstants.downloadsBox);
      _fileManager = FileManagerService(_metadata, _telegram, _hive);
      _syncQueue = SyncQueueService(_fileManager);
      _storageRepository = StorageRepository(_hive, _fileManager, _metadata);
      _thumbnailRepository = ThumbnailRepository(_telegram);
      _webShareQueue =
          WebShareQueueService(_downloadService, AppConstants.webSharesBox);
      _downloadFileUseCase = DownloadFileUseCase(_storageRepository);
      _generateWebShareUseCase = GenerateWebShareUseCase(_storageRepository);

      await NotificationService.instance.init();
      await NotificationService.instance.requestPermissions();

      _transferQueue.loadFromPersistence();
      unawaited(_downloadQueue.resumePendingDownloads());
      unawaited(_webShareQueue.resumePendingShares());

      // Process pending actions queue in the background
      _syncQueue.processQueue();

      _initialized = true;
      AppLogger.i('ServiceLocator initialized successfully',
          tag: 'ServiceLocator');
    } catch (e) {
      _initFuture = null;
      rethrow;
    }
  }

  /// Call on logout to clear all service state.
  void reset() {
    AppLogger.i('Resetting ServiceLocator', tag: 'ServiceLocator');
    LruFolderCacheService.instance.clear();
    TelegramRateLimiter.instance.reset();
    TransferQueueService.instance.clear();
    if (_initialized) {
      _thumbnailRepository.clearWebCache();
    }
    _initialized = false;
    _initFuture = null;
  }
}
