import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/telegram_service.dart';
import '../../../core/services/metadata_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/responsive.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _channelCtrl = TextEditingController();
  bool _isLoading = false;
  bool _showPass = false;
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _tokenCtrl.dispose();
    _channelCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);
    try {
      final result = await AuthService.instance.register(
        _emailCtrl.text.trim(),
        _passCtrl.text,
        _tokenCtrl.text.trim(),
        _channelCtrl.text.trim(),
      );
      if (result['success'] != true) {
        if (!mounted) return;
        _showError(result['message'] ?? 'Registration failed');
        return;
      }
      final telegram = TelegramService();
      await telegram.init(_tokenCtrl.text.trim(), _channelCtrl.text.trim());
      final meta = MetadataService(telegram);
      await meta.initMetadata(_emailCtrl.text.trim());
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pushReplacementNamed(AppRouter.home);
    } catch (e) {
      if (!mounted) return;
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppTheme.error,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = Responsive.isDesktop(context);
    return Scaffold(body: isDesktop ? _buildDesktop() : _buildMobile());
  }

  // ── Desktop ───────────────────────────────────────────────────────────────
  Widget _buildDesktop() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Expanded(child: _heroPanel()),
      Container(
        width: 520,
        color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        child: Center(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(48),
          child: _buildForm(isDesktop: true),
        )),
      ),
    ]);
  }

  Widget _heroPanel() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F0F1A), Color(0xFF1A1A2E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(children: [
          Positioned(
              top: -100,
              right: -60,
              child: _glowCircle(280, AppTheme.primary.withAlpha(35))),
          Positioned(
              bottom: -80,
              left: -40,
              child: _glowCircle(240, const Color(0xFFA78BFA).withAlpha(25))),
          Center(
              child: Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _logoBox(),
                  const SizedBox(height: 32),
                  Text('Get started\nfor free.',
                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          color: Colors.white, fontSize: 40, height: 1.2)),
                  const SizedBox(height: 16),
                  const Text(
                      'Your own unlimited cloud drive,\npowered by your Telegram channel.',
                      style: TextStyle(
                          color: Colors.white60, fontSize: 16, height: 1.6)),
                  const SizedBox(height: 40),
                  _instructionCard(),
                ]),
          )),
        ]),
      );

  Widget _instructionCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.primary.withAlpha(25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withAlpha(60)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.info_outline, color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Text('Quick Setup',
                style: TextStyle(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          ...[
            '1. Telegram → @BotFather → /newbot',
            '2. Create a private channel',
            '3. Add bot as admin with Pin Messages',
            '4. Copy Bot Token and Channel ID here'
          ].map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(s,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 13)),
              )),
        ]),
      );

  // ── Mobile ────────────────────────────────────────────────────────────────
  Widget _buildMobile() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Stack(children: [
        // Hero gradient header
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF0F0F1A), const Color(0xFF1A1A2E)]
                  : [const Color(0xFF6C63FF), const Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(
            top: -50,
            right: -40,
            child: _glowCircle(200, Colors.white.withAlpha(10))),

        SafeArea(
          child: Column(children: [
            // Back button
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
            // Brand in header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: FadeTransition(
                opacity: _fade,
                child: Row(children: [
                  _logoBox(size: 44, radius: 12, iconSize: 24),
                  const SizedBox(width: 12),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Create Account',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800)),
                        const Text('Set up in under a minute',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 13)),
                      ]),
                ]),
              ),
            ),

            // Form card
            Expanded(
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkBg : Colors.white,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(32)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withAlpha(40),
                            blurRadius: 40,
                            offset: const Offset(0, -4))
                      ],
                    ),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        28,
                        24,
                        MediaQuery.of(context).viewInsets.bottom + 24,
                      ),
                      child: _buildForm(isDesktop: false),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Form ──────────────────────────────────────────────────────────────────
  Widget _buildForm({required bool isDesktop}) {
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (isDesktop) ...[
          Text('Create your account',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          Text('Set up TelStorage in under a minute',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 32),
        ],

        // ── Account section ──────────────────────────────────────────────
        _sectionLabel('Account'),
        const SizedBox(height: 12),
        TextFormField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: _dec('Email address', Icons.email_outlined),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter email';
            if (!v.contains('@')) return 'Invalid email';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passCtrl,
          obscureText: !_showPass,
          textInputAction: TextInputAction.next,
          decoration: _dec('Password', Icons.lock_outline).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                  _showPass
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20),
              onPressed: () => setState(() => _showPass = !_showPass),
            ),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter password';
            if (v.length < 6) return 'Min 6 characters';
            return null;
          },
        ),
        const SizedBox(height: 24),

        // ── Telegram section ─────────────────────────────────────────────
        _sectionLabel('Telegram Bot'),
        const SizedBox(height: 8),
        _infoCard(
            'Get a Bot Token from @BotFather and your private Channel ID.'),
        const SizedBox(height: 12),
        TextFormField(
          controller: _tokenCtrl,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: _dec('Bot Token', Icons.key_rounded)
              .copyWith(hintText: '123456:ABC-DEF...'),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter bot token';
            if (!v.contains(':')) return 'Invalid token format';
            return null;
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _channelCtrl,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _register(),
          decoration: _dec('Channel ID', Icons.tag_rounded)
              .copyWith(hintText: '-1001234567890'),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Enter channel ID';
            if (!v.startsWith('-100')) return 'Should start with -100';
            return null;
          },
        ),
        const SizedBox(height: 28),

        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _register,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : const Text('Create Account',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Already have an account? ',
              style: Theme.of(context).textTheme.bodyMedium),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Text('Sign in',
                style: TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
      ]),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _logoBox(
          {double size = 64, double radius = 18, double iconSize = 36}) =>
      Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppTheme.primary, Color(0xFFA78BFA)]),
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
                color: AppTheme.primary.withAlpha(80),
                blurRadius: 16,
                offset: const Offset(0, 6))
          ],
        ),
        child:
            Icon(Icons.cloud_done_rounded, color: Colors.white, size: iconSize),
      );

  Widget _glowCircle(double size, Color color) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );

  Widget _sectionLabel(String text) => Text(text.toUpperCase(),
      style: TextStyle(
          color: AppTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2));

  Widget _infoCard(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withAlpha(50)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, color: AppTheme.primary, size: 18),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF3730A3),
                    fontSize: 12))),
      ]),
    );
  }
}
