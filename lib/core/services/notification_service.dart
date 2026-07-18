import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/transfer_task.dart';
import '../utils/app_logger.dart';

/// Service to handle local push notifications for file transfers (uploads and downloads).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  void Function(NotificationResponse)? onNotificationTap;

  bool _initialized = false;

  /// Initialize notification settings for Android and iOS.
  Future<void> init() async {
    if (_initialized) return;

    AppLogger.i('Initializing NotificationService...',
        tag: 'NotificationService');

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _notificationsPlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (details) {
          AppLogger.d('Notification tapped: ${details.payload}',
              tag: 'NotificationService');
          if (onNotificationTap != null) {
            onNotificationTap!(details);
          }
        },
      );
      _initialized = true;
      await _createNotificationChannel();
      AppLogger.i('NotificationService initialized successfully',
          tag: 'NotificationService');
    } catch (e) {
      AppLogger.e('Failed to initialize NotificationService: $e',
          tag: 'NotificationService', error: e);
    }
  }

  /// Request permissions for showing notifications.
  /// Recommended to call this upon successful login or home screen enter.
  Future<void> requestPermissions() async {
    try {
      // Android 13+ permission request
      final androidImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      // iOS permission request
      final iosImplementation =
          _notificationsPlugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosImplementation != null) {
        await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      AppLogger.w('Failed to request notification permissions: $e',
          tag: 'NotificationService');
    }
  }

  /// Display a standard push notification.
  Future<void> showNotification({
    int id = 0,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) {
      await init();
    }

    const androidDetails = AndroidNotificationDetails(
      'telstorage_transfers',
      'File Transfers',
      channelDescription: 'Notifications for download and upload completions',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      AppLogger.e('Failed to show notification: $e',
          tag: 'NotificationService', error: e);
    }
  }

  Future<void> _createNotificationChannel() async {
    const channel = AndroidNotificationChannel(
      'telstorage_transfers_v2',
      'Active Transfers',
      description: 'Real-time progress for uploads, downloads, and shares',
      importance:
          Importance.low, // Use low to avoid sound on every progress update
      showBadge: false,
      enableVibration: false,
      playSound: false,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Update the live transfer notification based on active tasks.
  Future<void> updateTransferNotification(
      List<TransferTask> activeTasks) async {
    if (!_initialized) await init();
    if (activeTasks.isEmpty) {
      await _notificationsPlugin.cancel(id: 999);
      return;
    }

    String title;
    String body;
    int progress = 0;
    bool indeterminate = false;
    List<AndroidNotificationAction> actions = [];

    if (activeTasks.length == 1) {
      final task = activeTasks.first;
      title = task.type == TransferType.upload
          ? 'Uploading Files...'
          : (task.type == TransferType.download
              ? 'Downloading Files...'
              : 'Sharing Files...');

      final speedText = task.speedKbps > 1024
          ? '${(task.speedKbps / 1024).toStringAsFixed(1)} MB/s'
          : '${task.speedKbps.toStringAsFixed(0)} KB/s';

      body = '${task.name}\n${(task.progress * 100).toInt()}% • $speedText';
      if (task.eta != null) body += ' • ${task.eta} remaining';

      progress = (task.progress * 100).toInt();

      if (task.status == TransferStatus.paused) {
        actions.add(AndroidNotificationAction('resume_${task.id}', 'Resume'));
      } else {
        actions.add(AndroidNotificationAction('pause_${task.id}', 'Pause'));
      }
      actions.add(AndroidNotificationAction('cancel_${task.id}', 'Cancel'));
    } else {
      title = '${activeTasks.length} Active Transfers';
      final uploads =
          activeTasks.where((t) => t.type == TransferType.upload).length;
      final downloads =
          activeTasks.where((t) => t.type == TransferType.download).length;
      final shares =
          activeTasks.where((t) => t.type == TransferType.share).length;

      List<String> parts = [];
      if (uploads > 0) parts.add('↑ $uploads uploads');
      if (downloads > 0) parts.add('↓ $downloads downloads');
      if (shares > 0) parts.add('🔗 $shares shares');
      body = parts.join(', ');

      double avgProgress = activeTasks.fold(0.0, (sum, t) => sum + t.progress) /
          activeTasks.length;
      progress = (avgProgress * 100).toInt();

      actions.add(const AndroidNotificationAction('view_all', 'View All'));
    }

    final androidDetails = AndroidNotificationDetails(
      'telstorage_transfers_v2',
      'Active Transfers',
      channelDescription:
          'Real-time progress for uploads, downloads, and shares',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      indeterminate: indeterminate,
      ongoing: true,
      autoCancel: false,
      category: AndroidNotificationCategory.progress,
      styleInformation: BigTextStyleInformation(body),
      actions: actions,
    );

    final details = NotificationDetails(android: androidDetails);

    try {
      await _notificationsPlugin.show(
        id: 999, // Constant ID for active transfers
        title: title,
        body: body,
        notificationDetails: details,
        payload: 'transfer_active',
      );
    } catch (e) {
      AppLogger.e('Failed to update transfer notification: $e',
          tag: 'NotificationService');
    }
  }

  Future<void> showCompletionNotification({
    required String title,
    required String body,
    String? payload,
    List<AndroidNotificationAction>? actions,
  }) async {
    if (!_initialized) await init();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'telstorage_completions',
        'Completions',
        channelDescription: 'Notifications for finished transfers',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.status,
        actions: actions,
      ),
    );

    await _notificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
