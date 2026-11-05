/*
 * File: app.dart
 * Description: Root TelStorage application widget configuring MultiBlocProvider, themes, and MaterialApp routing.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/routing/app_router.dart';
import 'core/services/auto_backup_lifecycle.dart';
import 'core/services/theme_service.dart';
import 'core/theme/app_theme.dart';
import 'core/services/auto_backup_scheduler.dart';
import 'core/services/error_log_service.dart';
import 'features/auth/presentation/viewmodels/auth_view_model.dart';
import 'features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'features/downloads/presentation/screens/downloads/viewmodel/downloads_view_model.dart';
import 'features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'features/upload/presentation/viewmodels/upload_view_model.dart';

/// Root Application Widget configuring theme listeners and Bloc providers.
class TelStorageApp extends StatefulWidget {
  /// Constructs TelStorageApp.
  const TelStorageApp({super.key});

  @override
  State<TelStorageApp> createState() => _TelStorageAppState();
}

class _TelStorageAppState extends State<TelStorageApp> {
  /// Lifecycle observer that consumes backup work after app resume.
  late final AutoBackupLifecycleObserver _backupLifecycleObserver;

  @override
  void initState() {
    super.initState();
    _backupLifecycleObserver = AutoBackupLifecycleObserver(
      onResume: () async {
        await ErrorLogService.instance.refresh();
        await AutoBackupScheduler.instance.consumeDueFlag();
      },
    );
    WidgetsBinding.instance.addObserver(_backupLifecycleObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_backupLifecycleObserver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc()..add(AppStarted()),
        ),
        BlocProvider<UploadBloc>(
          create: (context) {
            final bloc = UploadBloc();
            AutoBackupScheduler.instance.attachUploadBloc(bloc);
            // Process any due-flag armed by Workmanager while the app was dead.
            AutoBackupScheduler.instance.consumeDueFlag();
            return bloc;
          },
        ),
        BlocProvider<HomeCubit>(
          create: (context) => HomeCubit(),
        ),
        BlocProvider<TransferCubit>(
          create: (context) => TransferCubit(),
        ),
        BlocProvider<BrowserBloc>(
          create: (context) => BrowserBloc(),
        ),
      ],
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeService.instance.themeModeNotifier,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: 'TelStorage',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeMode,
            initialRoute: AppRouter.splash,
            onGenerateRoute: AppRouter.onGenerateRoute,
          );
        },
      ),
    );
  }
}
