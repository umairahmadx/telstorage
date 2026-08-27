/*
 * File: login_screen.dart
 * Description: Login view enabling user authentication via email & password.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../core/routing/app_router.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../viewmodels/auth_view_model.dart';

/// Screen component providing the login interface.
class LoginScreen extends StatefulWidget {
  /// Constructs the LoginScreen.
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// State controller for the LoginScreen with animation lifecycle management.
class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  /// Form validation key.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// Email input text controller.
  final TextEditingController _emailCtrl = TextEditingController();

  /// Password input text controller.
  final TextEditingController _passCtrl = TextEditingController();

  /// Focus node for the email field.
  final FocusNode _emailFocus = FocusNode();

  /// Focus node for the password field.
  final FocusNode _passFocus = FocusNode();

  /// Active error message displayed to the user.
  String? _errorMessage;

  /// Loading indicator state flag.
  bool _isLoading = false;

  /// Password visibility toggle flag.
  bool _showPass = false;

  /// Main entrance animation controller.
  late final AnimationController _anim;

  /// Fade-in animation driver.
  late final Animation<double> _fadeIn;

  /// Slide-up translation animation driver.
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeIn = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();

    _emailCtrl.addListener(_clearErrorOnTyping);
    _passCtrl.addListener(_clearErrorOnTyping);
  }

  void _clearErrorOnTyping() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_clearErrorOnTyping);
    _passCtrl.removeListener(_clearErrorOnTyping);
    _emailFocus.dispose();
    _passFocus.dispose();
    _anim.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// Dispatches the login event to the AuthBloc/AuthViewModel.
  void _login() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    context.read<AuthBloc>().add(
          LoginRequested(_emailCtrl.text.trim(), _passCtrl.text),
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return BlocConsumer<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          HapticFeedback.mediumImpact();
          Navigator.of(context).pushReplacementNamed(AppRouter.home);
        } else if (state is AuthError) {
          HapticFeedback.vibrate();
          setState(() {
            _errorMessage = state.message;
          });
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: colors.bgPrimary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state.message,
                      style: TextStyle(
                        color: colors.bgPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: colors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      },
      builder: (context, state) {
        _isLoading = state is AuthLoading;
        return Scaffold(
          body: _buildMobile(),
        );
      },
    );
  }

  /// Builds the mobile login layout.
  Widget _buildMobile() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(children: [
          // Full-screen gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors.heroGradient,
                begin: Alignment.topCenter,
                end: Alignment.center,
              ),
            ),
          ),
          // Decorative background glows
          Positioned(
              top: -60,
              right: -40,
              child: _glowCircle(220, colors.textPrimary.withAlpha(12))),
          Positioned(
              top: 80,
              left: -60,
              child: _glowCircle(180, AppColors.primary.withAlpha(40))),

          SafeArea(
            child: Column(children: [
              // Top hero section
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SlideTransition(
                    position: _slideUp,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _logoBox(56, 16, 30),
                        const SizedBox(height: 20),
                        Text('Welcome back',
                            style: Theme.of(context)
                                .textTheme
                                .headlineLarge
                                ?.copyWith(
                                    color: colors.textPrimary,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text('Sign in to your cloud drive',
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 15)),
                      ],
                    ),
                  ),
                ),
              ),

              // Sliding form card
              Expanded(
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.bgSurface,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                          color: colors.textPrimary.withAlpha(20),
                          blurRadius: 40,
                          spreadRadius: 0,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        24,
                        32,
                        24,
                        MediaQuery.of(context).viewInsets.bottom + 24,
                      ),
                      child: _buildForm(colors),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// Builds the login input form.
  Widget _buildForm(AppColorsExtension colors) {
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.error.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.error.withAlpha(90)),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    color: colors.error, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: colors.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon:
                      Icon(Icons.close_rounded, color: colors.error, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
                  onPressed: () => setState(() => _errorMessage = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 4),
        TextFormField(
          controller: _emailCtrl,
          focusNode: _emailFocus,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          onFieldSubmitted: (_) =>
              FocusScope.of(context).requestFocus(_passFocus),
          decoration: InputDecoration(
            labelText: 'Email address',
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Enter your email';
            if (!v.contains('@')) return 'Enter a valid email';
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passCtrl,
          focusNode: _passFocus,
          obscureText: !_showPass,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _login(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _showPass
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _showPass = !_showPass),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter your password';
            if (v.length < 6) return 'Password must be at least 6 characters';
            return null;
          },
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: colors.bgPrimary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: colors.bgPrimary))
                : const Text('Sign in',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  /// Builds branded logo container.
  Widget _logoBox(double size, double radius, double iconSize) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors.primaryGradient),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withAlpha(80),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
      ),
    );
  }

  /// Builds circular decorative ambient blur.
  Widget _glowCircle(double size, Color color) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}
