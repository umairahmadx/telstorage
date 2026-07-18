import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/theme_service.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/upload/bloc/upload_bloc.dart';
import 'features/home/bloc/home_cubit.dart';
import 'features/downloads/bloc/transfer_cubit.dart';

class TelStorageApp extends StatelessWidget {
  const TelStorageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (context) => AuthBloc()..add(AppStarted()),
        ),
        BlocProvider<UploadBloc>(
          create: (context) => UploadBloc(),
        ),
        BlocProvider<HomeCubit>(
          create: (context) => HomeCubit(),
        ),
        BlocProvider<TransferCubit>(
          create: (context) => TransferCubit(),
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
