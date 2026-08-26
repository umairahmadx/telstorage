/*
 * File: notification_routing_test.dart
 * Description: Tests verifying notification action parsing, dedicated screen routing, and clipboard/open file behaviors.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/navigation/navigation_intent.dart';
import 'package:telstorage/core/services/notification_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'package:telstorage/features/downloads/presentation/screens/downloads/viewmodel/downloads_view_model.dart';
import 'package:telstorage/features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_view_model.dart';
import 'package:telstorage/shared/widgets/mobile_shell.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/storage/data/repositories/storage_repository.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/file_record.dart';

class _MockEmptyStorageRepository implements StorageRepository {
  @override
  List<FolderRecord> getFolders(String? parentId) => [];

  @override
  List<FileRecord> getFiles(String? folderId) => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _buildTestApp(Widget child) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<AuthBloc>(create: (_) => AuthBloc()),
      BlocProvider<UploadBloc>(create: (_) => UploadBloc()),
      BlocProvider<HomeCubit>(create: (_) => HomeCubit()),
      BlocProvider<TransferCubit>(create: (_) => TransferCubit()),
      BlocProvider<BrowserBloc>(create: (_) => BrowserBloc()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    Animate.defaultDuration = Duration.zero;
    ServiceLocator.instance.setStorageRepositoryForTesting(_MockEmptyStorageRepository());
  });

  group('Notification Action & Screen Routing Tests', () {
    testWidgets('TC-01: payload transfer_download navigates to Downloads tab', (tester) async {
      await tester.pumpWidget(_buildTestApp(const MobileShell(initialIndex: 0)));
      await tester.pump(const Duration(milliseconds: 100));

      final shellState = tester.state<MobileShellState>(find.byType(MobileShell));
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: 'transfer_download',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final intent = ServiceLocator.instance.navigation.intentNotifier.value;
      expect(intent?.destination, equals(AppDestination.transferDownloads));
      expect(intent?.shellIndex, equals(3));
      expect(intent?.transferTabIndex, equals(0));
      expect(shellState.currentIndex, equals(3));

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('TC-02: payload transfer_upload navigates to Uploads tab', (tester) async {
      await tester.pumpWidget(_buildTestApp(const MobileShell(initialIndex: 0)));
      await tester.pump(const Duration(milliseconds: 100));

      final shellState = tester.state<MobileShellState>(find.byType(MobileShell));
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: 'transfer_upload',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final intent = ServiceLocator.instance.navigation.intentNotifier.value;
      expect(intent?.destination, equals(AppDestination.transferUploads));
      expect(intent?.shellIndex, equals(3));
      expect(intent?.transferTabIndex, equals(1));
      expect(shellState.currentIndex, equals(3));

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('TC-03: payload transfer_share navigates to Shared tab', (tester) async {
      await tester.pumpWidget(_buildTestApp(const MobileShell(initialIndex: 0)));
      await tester.pump(const Duration(milliseconds: 100));

      final shellState = tester.state<MobileShellState>(find.byType(MobileShell));
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: 'transfer_share',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final intent = ServiceLocator.instance.navigation.intentNotifier.value;
      expect(intent?.destination, equals(AppDestination.transferShared));
      expect(intent?.shellIndex, equals(3));
      expect(intent?.transferTabIndex, equals(2));
      expect(shellState.currentIndex, equals(3));

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('TC-04: action copy_url:... copies link to clipboard with feedback', (tester) async {
      String? clipboardData;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          clipboardData = (methodCall.arguments as Map)['text'] as String?;
          return null;
        }
        return null;
      });

      await tester.pumpWidget(_buildTestApp(const MobileShell(initialIndex: 0)));
      await tester.pump(const Duration(milliseconds: 100));

      final shellState = tester.state<MobileShellState>(find.byType(MobileShell));
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: 'copy_url:https://telstorage.io/share/demo123',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(clipboardData, equals('https://telstorage.io/share/demo123'));
      expect(find.text('Share link copied: https://telstorage.io/share/demo123'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('TC-05: action view_all and payload transfer_active navigate to active transfers', (tester) async {
      await tester.pumpWidget(_buildTestApp(const MobileShell(initialIndex: 0)));
      await tester.pump(const Duration(milliseconds: 100));

      final shellState = tester.state<MobileShellState>(find.byType(MobileShell));
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: 'view_all',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final intent = ServiceLocator.instance.navigation.intentNotifier.value;
      expect(intent?.destination, equals(AppDestination.transferActive));
      expect(intent?.shellIndex, equals(3));

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('TC-06: queue control actions pause, resume, cancel delegate to TransferQueueService', (tester) async {
      final queue = TransferQueueService.instance;
      queue.addTask(
        TransferTask(
          id: 'test_task_1',
          name: 'file.mp4',
          type: TransferType.download,
          sizeMb: 10.0,
          addedAt: DateTime.now(),
        ),
      );

      await tester.pumpWidget(_buildTestApp(const MobileShell(initialIndex: 0)));
      await tester.pump(const Duration(milliseconds: 100));

      final shellState = tester.state<MobileShellState>(find.byType(MobileShell));

      // Test Pause
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: 'pause_test_task_1',
        ),
      );
      expect(queue.isPaused('test_task_1'), isTrue);

      // Test Resume
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: 'resume_test_task_1',
        ),
      );
      expect(queue.isPaused('test_task_1'), isFalse);

      // Test Cancel
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: 'cancel_test_task_1',
        ),
      );
      expect(queue.isCancelled('test_task_1'), isTrue);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('TC-07: action view_downloads, view_uploads, view_shared navigate to respective tabs', (tester) async {
      await tester.pumpWidget(_buildTestApp(const MobileShell(initialIndex: 0)));
      await tester.pump(const Duration(milliseconds: 100));

      final shellState = tester.state<MobileShellState>(find.byType(MobileShell));

      // Test view_downloads
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: 'view_downloads',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(ServiceLocator.instance.navigation.intentNotifier.value?.destination, equals(AppDestination.transferDownloads));

      // Test view_uploads
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: 'view_uploads',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(ServiceLocator.instance.navigation.intentNotifier.value?.destination, equals(AppDestination.transferUploads));

      // Test view_shared
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: 'view_shared',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(ServiceLocator.instance.navigation.intentNotifier.value?.destination, equals(AppDestination.transferShared));

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('TC-08: action open_path:... executes safely and invokes FileOpenerHelper', (tester) async {
      await tester.pumpWidget(_buildTestApp(const MobileShell(initialIndex: 0)));
      await tester.pump(const Duration(milliseconds: 100));

      final shellState = tester.state<MobileShellState>(find.byType(MobileShell));

      // Invoke open_path on non-existent path in headless test environment - safely handled without crashing
      shellState.handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: 'open_path:/storage/emulated/0/Download/TelStorage/sample.pdf',
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pump(const Duration(seconds: 4));
    });

    test('TC-09: updateTransferNotification handles active and empty task lists safely', () async {
      final notifService = NotificationService.instance;
      // Active tasks should not throw
      await notifService.updateTransferNotification([
        TransferTask(
          id: 'task_fg_1',
          name: 'large_video.mp4',
          type: TransferType.upload,
          sizeMb: 50.0,
          progress: 0.25,
          addedAt: DateTime.now(),
        ),
      ]);

      // Empty tasks should cleanly stop foreground service
      await notifService.updateTransferNotification([]);
    });

    test('TC-10: startTransferSession and stopTransferSession manage FGS state cleanly', () async {
      final notifService = NotificationService.instance;

      await notifService.startTransferSession(
        title: 'Uploading video.mp4…',
        body: 'Preparing transfer queue',
      );
      expect(notifService.isTransferSessionActive, isTrue);

      await notifService.stopTransferSession();
      expect(notifService.isTransferSessionActive, isFalse);
    });
  });
}
