import 'package:flutter/material.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/browser/screens/browser_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

class AppRouter {
  static const String splash   = '/';
  static const String login    = '/login';
  static const String register = '/register';
  static const String home     = '/home';
  static const String browser  = '/browser';
  static const String settings = '/settings';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());

      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen());

      case home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());

      case browser:
        final folderId = settings.arguments as String?;
        return MaterialPageRoute(
          builder: (_) => BrowserScreen(currentFolderId: folderId),
        );

      case AppRouter.settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}
