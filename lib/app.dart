import 'package:flutter/material.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/theme_service.dart';

class TelStorageApp extends StatelessWidget {
  const TelStorageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
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
    );
  }
}
