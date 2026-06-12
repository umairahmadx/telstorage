import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/responsive.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _isLoading  = false;
  bool _showPass   = false;
  late final AnimationController _anim;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fadeIn  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);
    final result = await AuthService.instance.login(
      _emailCtrl.text.trim(), _passCtrl.text);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result['success'] == true) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushReplacementNamed(AppRouter.home);
    } else {
      HapticFeedback.vibrate();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['message'] ?? 'Login failed'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.error,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    return Scaffold(
      body: isDesktop ? _buildDesktop() : _buildMobile(),
    );
  }

  // ── Desktop layout (unchanged, already great) ─────────────────────────────
  Widget _buildDesktop() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Expanded(child: _heroPanel()),
      Container(
        width: 480,
        color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(48),
            child: _buildForm(isDesktop: true),
          ),
        ),
      ),
    ]);
  }

  Widget _heroPanel() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF0F0F1A), Color(0xFF1A1A2E), Color(0xFF16213E)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
    child: Stack(children: [
      Positioned(top: -80, left: -80,
          child: _glowCircle(300, AppTheme.primary.withAlpha(40))),
      Positioned(bottom: -100, right: -60,
          child: _glowCircle(250, const Color(0xFFA78BFA).withAlpha(30))),
      Center(child: Padding(padding: const EdgeInsets.all(48),
        child: Column(mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          _logoBox(64, 18, 36),
          const SizedBox(height: 32),
          Text('TelStorage', style: Theme.of(context).textTheme.displayLarge
              ?.copyWith(color: Colors.white, fontSize: 42)),
          const SizedBox(height: 12),
          Text('Unlimited cloud storage\npowered by Telegram.',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: Colors.white60, height: 1.6)),
          const SizedBox(height: 48),
          _featureRow(Icons.all_inclusive_rounded, 'Unlimited storage — no caps'),
          const SizedBox(height: 16),
          _featureRow(Icons.sync_rounded, 'Syncs across all your devices'),
          const SizedBox(height: 16),
          _featureRow(Icons.lock_rounded, 'Files stay in your Telegram channel'),
        ]),
      )),
    ]),
  );

  // ── Mobile layout (full redesign — immersive + ergonomic) ─────────────────
  Widget _buildMobile() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Stack(children: [
        // Full-screen gradient background
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF0F0F1A), const Color(0xFF1A1A2E)]
                  : [const Color(0xFF6C63FF), const Color(0xFF4F46E5)],
              begin: Alignment.topCenter, end: Alignment.center,
            ),
          ),
        ),
        // Decorative blobs
        Positioned(top: -60, right: -40,
            child: _glowCircle(220, Colors.white.withAlpha(12))),
        Positioned(top: 80, left: -60,
            child: _glowCircle(180, AppTheme.primary.withAlpha(40))),

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
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(color: Colors.white, fontSize: 32,
                                  fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('Sign in to your cloud drive',
                          style: const TextStyle(color: Colors.white70, fontSize: 15)),
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
                    color: isDark ? AppTheme.darkBg : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(40),
                        blurRadius: 40, spreadRadius: 0, offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      24, 32, 24,
                      MediaQuery.of(context).viewInsets.bottom + 24,
                    ),
                    child: _buildForm(isDesktop: false),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Shared form ───────────────────────────────────────────────────────────
  Widget _buildForm({required bool isDesktop}) {
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (isDesktop) ...[ 
          Text('Sign in', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Enter your credentials to continue',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 36),
        ] else ...[
          const SizedBox(height: 4),
        ],
        TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Email address',
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter your email';
            if (!v.contains('@')) return 'Enter a valid email';
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _passCtrl,
          obscureText: !_showPass,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _login(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                _showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 20,
              ),
              onPressed: () => setState(() => _showPass = !_showPass),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter your password';
            return null;
          },
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Sign in',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────
  Widget _logoBox(double size, double radius, double iconSize) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [AppTheme.primary, Color(0xFFA78BFA)]),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [BoxShadow(color: AppTheme.primary.withAlpha(80),
          blurRadius: 20, offset: const Offset(0, 8))],
    ),
    child: Icon(Icons.cloud_done_rounded, color: Colors.white, size: iconSize),
  );

  Widget _glowCircle(double size, Color color) => Container(
    width: size, height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  Widget _featureRow(IconData icon, String text) => Row(children: [
    Container(width: 32, height: 32,
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(40),
        borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: AppTheme.primary, size: 18)),
    const SizedBox(width: 12),
    Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14)),
  ]);
}
