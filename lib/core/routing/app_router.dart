import 'package:flutter/material.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/browser/screens/browser_screen.dart';
import '../../features/downloads/screens/downloads_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../shared/widgets/mobile_shell.dart';
import '../services/auth_service.dart';

class AppRouter {
  static const String splash    = '/';
  static const String login     = '/login';
  static const String register  = '/register';
  static const String home      = '/home';
  static const String browser   = '/browser';
  static const String downloads = '/downloads';
  static const String settings  = '/settings';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _pageRoute(const SplashScreen(), settings);

      case login:
        return _pageRoute(const LoginScreen(), settings);

      case home:
        final initialTab = settings.arguments as int? ?? 0;
        return _pageRoute(MobileShell(initialIndex: initialTab), settings);

      case browser:
        final folderId = settings.arguments as String?;
        return _pageRoute(
          BrowserScreen(currentFolderId: folderId),
          settings,
        );

      case downloads:
        return _pageRoute(const DownloadsScreen(), settings);

      case AppRouter.settings:
        return _pageRoute(const SettingsScreen(), settings);

      default:
        return _pageRoute(const FallbackRedirectorScreen(), settings);
    }
  }

  static Route<dynamic> _pageRoute(Widget child, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.08, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;
        final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
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

/// Dynamic redirector screen for fallback routes.
class FallbackRedirectorScreen extends StatefulWidget {
  const FallbackRedirectorScreen({super.key});

  @override
  State<FallbackRedirectorScreen> createState() => _FallbackRedirectorScreenState();
}

class _FallbackRedirectorScreenState extends State<FallbackRedirectorScreen> {
  @override
  void initState() {
    super.initState();
    _redirect();
  }

  Future<void> _redirect() async {
    final isLoggedIn = await AuthService.instance.isLoggedIn();
    if (!mounted) return;
    if (isLoggedIn) {
      Navigator.of(context).pushReplacementNamed(AppRouter.home);
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
