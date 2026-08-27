/*
 * File: splash_screen.dart
 * Description: Splash view displayed on startup to verify authentication and initialize services.
 */

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../../core/routing/app_router.dart';
import '../../../../../core/services/auth_service.dart';
import '../../../../../core/services/service_locator.dart';
import '../../../../../core/theme/app_theme.dart';

/// Screen component shown during initial app boot.
class SplashScreen extends StatefulWidget {
  /// Constructs the SplashScreen.
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// State controller for SplashScreen handling initial session redirection.
class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  /// Verifies active session and routes user accordingly.
  Future<void> _checkAuth() async {
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
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors.heroGradient,
            ),
          ),
          child: Stack(
            children: [
              // Decorative glow circles
              Positioned(
                top: -60,
                right: -40,
                child: _glowCircle(180, AppColors.primary.withAlpha(30)),
              ),
              Positioned(
                bottom: -80,
                left: -50,
                child: _glowCircle(220, colors.glowColor),
              ),
              Positioned(
                top: MediaQuery.of(context).size.height * 0.3,
                left: -30,
                child: _glowCircle(100, AppColors.primary.withAlpha(20)),
              ),

              // Main content
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo with gradient container
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: colors.primaryGradient,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: colors.glowColor,
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset('assets/images/logo.png',
                            fit: BoxFit.cover),
                      ),
                    )
                        .animate()
                        .fadeIn(
                          duration: 400.ms,
                          curve: Curves.easeOutCubic,
                        )
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1.0, 1.0),
                          duration: 400.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    const SizedBox(height: 28),

                    // App name
                    Text(
                      'TelStorage',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: colors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    )
                        .animate()
                        .fadeIn(
                          duration: 400.ms,
                        )
                        .slideY(
                          begin: 0.2,
                          end: 0,
                          duration: 400.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    const SizedBox(height: 8),

                    // Subtitle
                    Text(
                      'Unlimited Cloud Storage',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: colors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    )
                        .animate()
                        .fadeIn(
                          duration: 400.ms,
                        )
                        .slideY(
                          begin: 0.2,
                          end: 0,
                          duration: 400.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    const SizedBox(height: 56),

                    // Loading indicator
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.accentPrimary,
                        ),
                      ),
                    ).animate().fadeIn(
                          duration: 300.ms,
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds blurred decorative background glow.
  Widget _glowCircle(double size, Color color) => ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      );
}
