import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              colors: isDark
                  ? const [Color(0xFF0F0F1A), Color(0xFF1A1A2E)]
                  : const [AppTheme.primary, Color(0xFF4F46E5)],
            ),
          ),
          child: Stack(
            children: [
              // Decorative glow circles
              Positioned(
                top: -60,
                right: -40,
                child: _glowCircle(180, AppTheme.primary.withAlpha(30)),
              ),
              Positioned(
                bottom: -80,
                left: -50,
                child: _glowCircle(220, const Color(0xFFA78BFA).withAlpha(25)),
              ),
              Positioned(
                top: MediaQuery.of(context).size.height * 0.3,
                left: -30,
                child: _glowCircle(100, AppTheme.primary.withAlpha(20)),
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
                          colors: isDark
                              ? const [AppTheme.primary, Color(0xFFA78BFA)]
                              : const [Colors.white24, Colors.white38],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? AppTheme.primary.withAlpha(80)
                                : Colors.black.withAlpha(30),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.cloud_done_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    )
                        .animate()
                        .fadeIn(
                          duration: 600.ms,
                          curve: Curves.easeOutCubic,
                        )
                        .scale(
                          begin: const Offset(0.8, 0.8),
                          end: const Offset(1.0, 1.0),
                          duration: 600.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    const SizedBox(height: 28),

                    // App name
                    const Text(
                      'TelStorage',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    )
                        .animate()
                        .fadeIn(
                          delay: 300.ms,
                          duration: 500.ms,
                        )
                        .slideY(
                          begin: 0.3,
                          end: 0,
                          delay: 300.ms,
                          duration: 500.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    const SizedBox(height: 8),

                    // Subtitle
                    const Text(
                      'Unlimited Cloud Storage',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: Colors.white70,
                        letterSpacing: 0.3,
                      ),
                    )
                        .animate()
                        .fadeIn(
                          delay: 500.ms,
                          duration: 500.ms,
                        )
                        .slideY(
                          begin: 0.3,
                          end: 0,
                          delay: 500.ms,
                          duration: 500.ms,
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
                          isDark
                              ? AppTheme.primary
                              : Colors.white.withAlpha(200),
                        ),
                      ),
                    ).animate().fadeIn(
                          delay: 800.ms,
                          duration: 400.ms,
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
