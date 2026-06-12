import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/app_logger.dart';

/// Service to handle local push notifications for file transfers (uploads and downloads).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize notification settings for Android and iOS.
  Future<void> init() async {
    if (_initialized) return;

    AppLogger.i('Initializing NotificationService...', tag: 'NotificationService');

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
          AppLogger.d('Notification tapped: ${details.payload}', tag: 'NotificationService');
        },
      );
      _initialized = true;
      AppLogger.i('NotificationService initialized successfully', tag: 'NotificationService');
    } catch (e) {
      AppLogger.e('Failed to initialize NotificationService: $e', tag: 'NotificationService', error: e);
    }
  }

  /// Request permissions for showing notifications.
  /// Recommended to call this upon successful login or home screen enter.
  Future<void> requestPermissions() async {
    try {
      // Android 13+ permission request
      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      // iOS permission request
      final iosImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (iosImplementation != null) {
        await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } catch (e) {
      AppLogger.w('Failed to request notification permissions: $e', tag: 'NotificationService');
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
      AppLogger.e('Failed to show notification: $e', tag: 'NotificationService', error: e);
    }
  }
}
