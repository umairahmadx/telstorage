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

  TelegramService get telegram => _telegram;
  HiveService get hive => _hive;
  MetadataService get metadata => _metadata;
  SyncService get syncService => _syncService;
  UploadService get uploadService => _uploadService;
  DownloadService get downloadService => _downloadService;
  DownloadQueueService get downloadQueue => _downloadQueue;
  FileManagerService get fileManager => _fileManager;

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

    final token = await storage.read(key: 'bot_token');
    final channelId = await storage.read(key: 'channel_id');

    if (token == null || channelId == null) {
      _initFuture = null;
      throw Exception('Bot credentials not found in secure storage. Please log in again.');
    }

    try {
      _telegram = TelegramService();
      await _telegram.init(token, channelId);

      _hive = HiveService.instance;

      _metadata = MetadataService(_telegram);
      _syncService = SyncService(_metadata, _telegram, _hive);
      _uploadService = UploadService(_telegram, _metadata, _hive);
      _downloadService = DownloadService(_telegram);
      _downloadQueue = DownloadQueueService(_downloadService, AppConstants.downloadsBox);
      _fileManager = FileManagerService(_metadata, _telegram, _hive);

      await NotificationService.instance.init();
      await NotificationService.instance.requestPermissions();

      _initialized = true;
      AppLogger.i('ServiceLocator initialized successfully', tag: 'ServiceLocator');
    } catch (e) {
      _initFuture = null;
      rethrow;
    }
  }

  /// Call on logout to clear all service state.
  void reset() {
    AppLogger.i('Resetting ServiceLocator', tag: 'ServiceLocator');
    _initialized = false;
    _initFuture = null;
  }
}
