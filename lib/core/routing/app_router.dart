/*
 * File: app_router.dart
 * Description: Global application router handling route generation and smooth page transitions.
 */

import 'package:flutter/material.dart';
import '../../features/auth/presentation/screens/login/login_screen.dart';
import '../../features/auth/presentation/screens/splash/splash_screen.dart';
import '../../features/browser/presentation/screens/browser/browser_screen.dart';
import '../../features/downloads/presentation/screens/downloads/downloads_screen.dart';
import '../../features/settings/presentation/screens/error_logs/error_logs_screen.dart';

import '../../features/settings/presentation/screens/settings/settings_screen.dart';
import '../../shared/widgets/mobile_shell.dart';
import '../services/auth_service.dart';
import '../services/service_locator.dart';

/// Central route manager with route names and onGenerateRoute handler.
class AppRouter {
  /// Splash initial route path.
  static const String splash = '/';

  /// Login route path.
  static const String login = '/login';

  /// Register route path.
  static const String register = '/register';

  /// Main shell home route path.
  static const String home = '/home';

  /// File browser route path.
  static const String browser = '/browser';

  /// Downloads & transfers route path.
  static const String downloads = '/downloads';

  /// Settings control center route path.
  static const String settings = '/settings';

  /// Error & diagnostic logs route path.
  static const String errorLogs = '/settings/error-logs';

  /// Generates the requested route dynamically with transition effects.
  static Route<dynamic> onGenerateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case splash:
        return _pageRoute(const SplashScreen(), routeSettings);

      case login:
        return _pageRoute(const LoginScreen(), routeSettings);

      case home:
        final initialTab = routeSettings.arguments as int? ?? 0;
        return _pageRoute(MobileShell(initialIndex: initialTab), routeSettings);

      case browser:
        String? folderId;
        String? category;
        if (routeSettings.arguments is String) {
          folderId = routeSettings.arguments as String;
        } else if (routeSettings.arguments is Map<String, dynamic>) {
          final args = routeSettings.arguments as Map<String, dynamic>;
          folderId = args['folderId'] as String?;
          category = args['category'] as String?;
        }
        return _pageRoute(
          BrowserScreen(currentFolderId: folderId, category: category),
          routeSettings,
        );

      case downloads:
        return _pageRoute(const DownloadsScreen(), routeSettings);

      case AppRouter.settings:
        return _pageRoute(const SettingsScreen(), routeSettings);

      case errorLogs:
        return _pageRoute(const ErrorLogsScreen(), routeSettings);


      default:
        return _pageRoute(const FallbackRedirectorScreen(), routeSettings);
    }
  }

  /// Builds a smooth sliding fade page route transition.
  static Route<dynamic> _pageRoute(Widget child, RouteSettings routeSettings) {
    return PageRouteBuilder(
      settings: routeSettings,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.08, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;
        final tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        return SlideTransition(
          position: animation.drive(tween),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 200),
    );
  }
}

/// Dynamic redirector screen for fallback and unmatched routes.
class FallbackRedirectorScreen extends StatefulWidget {
  /// Constructs FallbackRedirectorScreen.
  const FallbackRedirectorScreen({super.key});

  @override
  State<FallbackRedirectorScreen> createState() =>
      _FallbackRedirectorScreenState();
}

/// State controller for FallbackRedirectorScreen.
class _FallbackRedirectorScreenState extends State<FallbackRedirectorScreen> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  /// Verifies active session and redirects.
  Future<void> _redirect() async {
    final isLoggedIn = await AuthService.instance.isLoggedIn();
    if (!mounted) return;
    if (isLoggedIn) {
      try {
        await ServiceLocator.instance.init();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AppRouter.home);
      } catch (e) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AppRouter.login);
      }
    } else {
      Navigator.of(context).pushReplacementNamed(AppRouter.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
