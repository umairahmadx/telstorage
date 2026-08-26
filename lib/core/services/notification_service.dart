/*
 * File: notification_service.dart
 * Description: Component and logic definition for notification_service.dart in TelStorage.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
  bool _initAttempted = false;
  bool _fgsActive = false;

  /// Returns whether a foreground transfer session is currently running.
  bool get isTransferSessionActive => _fgsActive;

  /// Allows tests or custom harnesses to mock initialization state and bypass platform channels.
  @visibleForTesting
  static void setMockInitialized(bool value) {
    instance._initialized = value;
    instance._initAttempted = true;
  }

  /// Initialize notification settings for Android and iOS.
  Future<void> init() async {
    if (_initialized || _initAttempted) return;
    _initAttempted = true;

    AppLogger.i('Initializing NotificationService...',
        tag: 'NotificationService');

    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
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
      AppLogger.w('Failed to initialize NotificationService: $e',
          tag: 'NotificationService');
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

  /// Returns the notification response that launched the app from terminated state, if any.
  Future<NotificationResponse?> getAppLaunchNotificationDetails() async {
    if (!_initialized) return null;
    try {
      final details =
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        return details?.notificationResponse;
      }
    } catch (e) {
      AppLogger.w('Failed to get launch notification details: $e',
          tag: 'NotificationService');
    }
    return null;
  }

  /// Display a standard push notification.
  Future<void> showNotification({
    int id = 0,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized && !_initAttempted) {
      await init();
    }
    if (!_initialized) return;

    const androidDetails = AndroidNotificationDetails(
      'telstorage_completions_v2',
      'Completions',
      channelDescription: 'Notifications for finished transfers and alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/launcher_icon',
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
    const activeChannel = AndroidNotificationChannel(
      'telstorage_transfers_v2',
      'Active Transfers',
      description: 'Real-time progress for uploads, downloads, and shares',
      importance:
          Importance.low, // Use low to avoid sound on every progress update
      showBadge: false,
      enableVibration: false,
      playSound: false,
    );

    const completionChannel = AndroidNotificationChannel(
      'telstorage_completions_v2',
      'Completions',
      description: 'Notifications for finished downloads, uploads, and shares',
      importance: Importance.high,
      showBadge: true,
      enableVibration: true,
      playSound: true,
    );

    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(activeChannel);
    await androidPlugin?.createNotificationChannel(completionChannel);
  }

  /// Proactively starts the Android Foreground Service and CPU wakelock in foreground context.
  /// Must be invoked synchronously when user triggers upload/transfers to satisfy Android 12+ FGS policies.
  Future<void> startTransferSession({String? title, String? body}) async {
    if (_fgsActive) return;
    try {
      if (!_initialized && !_initAttempted) await init();
      _fgsActive = true;

      try {
        await WakelockPlus.enable();
      } catch (_) {}

      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      const androidDetails = AndroidNotificationDetails(
        'telstorage_transfers_v2',
        'Active Transfers',
        channelDescription:
            'Real-time progress for uploads, downloads, and shares',
        importance: Importance.low,
        priority: Priority.low,
        icon: '@mipmap/launcher_icon',
        onlyAlertOnce: true,
        showProgress: true,
        maxProgress: 100,
        progress: 0,
        indeterminate: true,
        ongoing: true,
        autoCancel: false,
        category: AndroidNotificationCategory.progress,
      );

      if (androidPlugin != null) {
        await androidPlugin.startForegroundService(
          id: 999,
          title: title ?? 'Preparing Transfers…',
          body: body ?? 'Starting background transfer session',
          notificationDetails: androidDetails,
          payload: 'transfer_active',
          foregroundServiceTypes: {
            AndroidServiceForegroundType.foregroundServiceTypeDataSync,
          },
        );
      }
    } catch (e) {
      AppLogger.d('Failed to start proactive transfer session: $e',
          tag: 'NotificationService');
    }
  }

  /// Stops the active Android Foreground Service session, releases CPU wakelock, and cancels notification.
  Future<void> stopTransferSession() async {
    if (!_fgsActive) return;
    _fgsActive = false;
    try {
      try {
        await WakelockPlus.disable();
      } catch (_) {}

      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.stopForegroundService();
      await _notificationsPlugin.cancel(id: 999);
    } catch (e) {
      AppLogger.d('Failed to stop transfer session: $e',
          tag: 'NotificationService');
    }
  }

  /// Update the live transfer notification based on active tasks.
  Future<void> updateTransferNotification(
      List<TransferTask> activeTasks) async {
    try {
      if (!_initialized && !_initAttempted) await init();
      if (!_initialized) return;
      if (activeTasks.isEmpty) {
        await stopTransferSession();
        return;
      }

      _fgsActive = true;
      try {
        await WakelockPlus.enable();
      } catch (_) {}

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
          actions.add(AndroidNotificationAction(
            'resume_${task.id}',
            'Resume',
            showsUserInterface: false,
          ));
        } else {
          actions.add(AndroidNotificationAction(
            'pause_${task.id}',
            'Pause',
            showsUserInterface: false,
          ));
        }
        actions.add(AndroidNotificationAction(
          'cancel_${task.id}',
          'Cancel',
          showsUserInterface: false,
        ));
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

        double avgProgress =
            activeTasks.fold(0.0, (sum, t) => sum + t.progress) /
                activeTasks.length;
        progress = (avgProgress * 100).toInt();

        actions.add(const AndroidNotificationAction(
          'view_all',
          'View All',
          showsUserInterface: true,
        ));
      }

      final androidDetails = AndroidNotificationDetails(
        'telstorage_transfers_v2',
        'Active Transfers',
        channelDescription:
            'Real-time progress for uploads, downloads, and shares',
        importance: Importance.low,
        priority: Priority.low,
        icon: '@mipmap/launcher_icon',
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

      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        await androidPlugin.startForegroundService(
          id: 999,
          title: title,
          body: body,
          notificationDetails: androidDetails,
          payload: 'transfer_active',
          foregroundServiceTypes: {
            AndroidServiceForegroundType.foregroundServiceTypeDataSync,
          },
        );
      } else {
        final details = NotificationDetails(android: androidDetails);
        await _notificationsPlugin.show(
          id: 999, // Constant ID for active transfers
          title: title,
          body: body,
          notificationDetails: details,
          payload: 'transfer_active',
        );
      }
    } catch (e) {
      AppLogger.d(
          'Skipping transfer notification update in test/uninitialized environment: $e',
          tag: 'NotificationService');
    }
  }

  /// Shows a high-priority transfer completion or failure notification.
  Future<void> showCompletionNotification({
    required String title,
    required String body,
    String? payload,
    List<AndroidNotificationAction>? actions,
  }) async {
    if (!_initialized && !_initAttempted) await init();
    if (!_initialized) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'telstorage_completions_v2',
        'Completions',
        channelDescription: 'Notifications for finished transfers',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
        category: AndroidNotificationCategory.status,
        actions: actions,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
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
