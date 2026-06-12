import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/theme_service.dart';
import '../../../shared/utils/responsive.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/mobile_shell.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final scaffold = _buildScaffold(context);
    if (isMobile) return scaffold;
    return AppShell(selectedIndex: 2, child: scaffold);
  }

  Scaffold _buildScaffold(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        automaticallyImplyLeading: !isMobile,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
        children: isMobile
            ? _buildMobileContent(isDark)
            : _buildDesktopContent(isDark),
      ),
    );
  }

  /// Desktop layout — unchanged from original
  List<Widget> _buildDesktopContent(bool isDark) {
    return [
      const _SectionHeader('About'),
      _GlassCard(children: [
        const _InfoTile(Icons.cloud_done_rounded, AppTheme.primary, 'TelStorage',
            'Telegram-powered unlimited cloud storage'),
        _Divider(isDark),
        const _InfoTile(Icons.all_inclusive_rounded, AppTheme.success,
            'Storage Limit', 'Unlimited — no caps, ever'),
        _Divider(isDark),
        const _InfoTile(Icons.lock_rounded, AppTheme.secondary, 'Security',
            'Files live in your private Telegram channel'),
      ]),
      const SizedBox(height: 24),
      const _SectionHeader('Storage'),
      _GlassCard(children: [
        _ActionTile(
          Icons.sync_rounded,
          const Color(0xFF6C63FF),
          'Sync Files',
          'Pull latest file list from Telegram',
          _syncing ? null : () => _syncFiles(),
          trailing: _syncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        _Divider(isDark),
        _ActionTile(
          Icons.folder_open_rounded,
          const Color(0xFFF59E0B),
          'Browse Files',
          'Open the file browser',
          () => Navigator.of(context).pushNamed(AppRouter.browser),
        ),
      ]),
      const SizedBox(height: 24),
      const _SectionHeader('Appearance'),
      _GlassCard(children: [
        _ActionTile(
          isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          isDark ? const Color(0xFF818CF8) : const Color(0xFFF59E0B),
          'Dark Mode',
          'Toggle between dark and light themes',
          () => ThemeService.instance.toggleTheme(context),
          trailing: Switch(
            value: isDark,
            onChanged: (_) => ThemeService.instance.toggleTheme(context),
            activeThumbColor: AppTheme.primary,
          ),
        ),
      ]),
      const SizedBox(height: 24),
      const _SectionHeader('Account'),
      _GlassCard(
        borderColor: AppTheme.error.withAlpha(80),
        children: [
          _ActionTile(
            Icons.logout_rounded,
            AppTheme.error,
            'Log Out',
            'Your files remain safely on Telegram',
            () => _logout(),
            titleColor: AppTheme.error,
          ),
        ],
      ),
      const SizedBox(height: 40),
      Center(
        child: Text('TelStorage v1.0.0  ·  Flutter + Telegram',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center),
      ),
    ];
  }

  /// Mobile layout — with profile header, reordered sections, and staggered animations
  List<Widget> _buildMobileContent(bool isDark) {
    int animIndex = 0;
    Widget animated(Widget child) {
      final delay = (animIndex * 80).ms;
      animIndex++;
      return child
          .animate()
          .fadeIn(delay: delay, duration: 350.ms, curve: Curves.easeOut)
          .slideY(
              begin: 0.08,
              end: 0,
              delay: delay,
              duration: 350.ms,
              curve: Curves.easeOut);
    }

    return [
      // Profile / App branding header card
      animated(_buildBrandingCard(isDark)),
      const SizedBox(height: 24),

      // Storage section
      animated(const _SectionHeader('Storage')),
      animated(_GlassCard(children: [
        _ActionTile(
          Icons.sync_rounded,
          const Color(0xFF6C63FF),
          'Sync Files',
          'Pull latest file list from Telegram',
          _syncing ? null : () => _syncFiles(),
          trailing: _syncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        _Divider(isDark),
        _ActionTile(
          Icons.folder_open_rounded,
          const Color(0xFFF59E0B),
          'Browse Files',
          'Open the file browser',
          () {
            final shell = MobileShell.of(context);
            if (shell != null) {
              shell.switchTab(1); // Files tab
            } else {
              Navigator.of(context).pushNamed(AppRouter.browser);
            }
          },
        ),
      ])),
      const SizedBox(height: 24),

      // About section (moved after Storage)
      animated(const _SectionHeader('About')),
      animated(_GlassCard(children: [
        const _InfoTile(Icons.all_inclusive_rounded, AppTheme.success,
            'Storage Limit', 'Unlimited — no caps, ever'),
        _Divider(isDark),
        const _InfoTile(Icons.lock_rounded, AppTheme.secondary, 'Security',
            'Files live in your private Telegram channel'),
      ])),
      const SizedBox(height: 24),

      // Appearance section
      animated(const _SectionHeader('Appearance')),
      animated(_GlassCard(children: [
        _ActionTile(
          isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
          isDark ? const Color(0xFF818CF8) : const Color(0xFFF59E0B),
          'Dark Mode',
          'Toggle between dark and light themes',
          () => ThemeService.instance.toggleTheme(context),
          trailing: Switch(
            value: isDark,
            onChanged: (_) => ThemeService.instance.toggleTheme(context),
            activeThumbColor: AppTheme.primary,
          ),
        ),
      ])),
      const SizedBox(height: 24),

      // Account section
      animated(const _SectionHeader('Account')),
      animated(_GlassCard(
        borderColor: AppTheme.error.withAlpha(80),
        children: [
          _ActionTile(
            Icons.logout_rounded,
            AppTheme.error,
            'Log Out',
            'Your files remain safely on Telegram',
            () => _logout(),
            titleColor: AppTheme.error,
          ),
        ],
      )),
      const SizedBox(height: 40),

      animated(Center(
        child: Text('TelStorage v1.0.0  ·  Flutter + Telegram',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center),
      )),
    ];
  }

  Widget _buildBrandingCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? const [Color(0xFF1E1E35), Color(0xFF252545)]
              : const [Color(0xFFEDE9FF), Color(0xFFF0F0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Row(
        children: [
          // Gradient logo
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, Color(0xFFA78BFA)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withAlpha(60),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(
              Icons.cloud_done_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TelStorage',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Telegram-powered cloud storage',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFF6B7280),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncFiles() async {
    if (!ServiceLocator.instance.isInitialized) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please log in first to sync'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _syncing = true);
    try {
      final result =
          await ServiceLocator.instance.syncService.syncFromTelegram();
      if (!mounted) return;
      final msg = result.hasChanges
          ? 'Sync complete: +${result.added} added, −${result.removed} removed'
          : 'Already up to date';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.success,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sync failed: $e'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.error,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log out?'),
        content: const Text(
            'Your files are safely stored on Telegram. You can log back in anytime.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final nav = Navigator.of(context);
      await AuthService.instance.logout();
      nav.pushReplacementNamed(AppRouter.login);
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      );
}

class _GlassCard extends StatelessWidget {
  final List<Widget> children;
  final Color? borderColor;
  const _GlassCard({required this.children, this.borderColor});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: borderColor ??
                (isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder)),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider(this.isDark);
  @override
  Widget build(BuildContext context) => Divider(
      indent: 56,
      height: 1,
      color: isDark ? const Color(0xFF2A2A45) : const Color(0xFFE8E4FF));
}

Widget _iconBox(IconData icon, Color color) => Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
          color: color.withAlpha(25), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 20),
    );

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  const _InfoTile(this.icon, this.color, this.title, this.subtitle);
  @override
  Widget build(BuildContext context) => ListTile(
        leading: _iconBox(icon, color),
        title: Text(title, style: Theme.of(context).textTheme.labelLarge),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Color? titleColor;
  final Widget? trailing;
  const _ActionTile(
      this.icon, this.color, this.title, this.subtitle, this.onTap,
      {this.titleColor, this.trailing});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: _iconBox(icon, color),
        title: Text(title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: titleColor)),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: onTap,
      );
}
