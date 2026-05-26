import 'package:flutter/material.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/responsive.dart';
import '../../../shared/widgets/app_shell.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final scaffold = _buildScaffold(context);
    if (isMobile) return scaffold;
    return AppShell(selectedIndex: 2, child: scaffold);
  }

  Scaffold _buildScaffold(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        automaticallyImplyLeading: Responsive.isMobile(context),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
        children: [
          _SectionHeader('About'),
          _GlassCard(children: [
            _InfoTile(Icons.cloud_done_rounded, AppTheme.primary,
                'TelStorage', 'Telegram-powered unlimited cloud storage'),
            _Divider(isDark),
            _InfoTile(Icons.all_inclusive_rounded, AppTheme.success,
                'Storage Limit', 'Unlimited — no caps, ever'),
            _Divider(isDark),
            _InfoTile(Icons.lock_rounded, AppTheme.secondary,
                'Security', 'Files live in your private Telegram channel'),
          ]),
          const SizedBox(height: 24),

          _SectionHeader('Storage'),
          _GlassCard(children: [
            _ActionTile(
              Icons.sync_rounded, const Color(0xFF6C63FF),
              'Sync Files', 'Pull latest file list from Telegram',
              () { Navigator.of(context).pop(); },
            ),
            _Divider(isDark),
            _ActionTile(
              Icons.folder_open_rounded, const Color(0xFFF59E0B),
              'Browse Files', 'Open the file browser',
              () => Navigator.of(context).pushNamed(AppRouter.browser),
            ),
          ]),
          const SizedBox(height: 24),

          _SectionHeader('Appearance'),
          _GlassCard(children: [
            _InfoTile(
              isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              isDark ? const Color(0xFF818CF8) : const Color(0xFFF59E0B),
              isDark ? 'Dark Mode Active' : 'Light Mode Active',
              'Change in your device/browser settings',
            ),
          ]),
          const SizedBox(height: 24),

          _SectionHeader('Account'),
          _GlassCard(
            borderColor: AppTheme.error.withAlpha(80),
            children: [
              _ActionTile(
                Icons.logout_rounded, AppTheme.error,
                'Log Out', 'Your files remain safely on Telegram',
                () => _logout(context),
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
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log out?'),
        content: const Text(
            'Your files are safely stored on Telegram. You can log back in anytime.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
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
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
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
      indent: 56, height: 1,
      color: isDark ? const Color(0xFF2A2A45) : const Color(0xFFE8E4FF));
}

Widget _iconBox(IconData icon, Color color) => Container(
  width: 36, height: 36,
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
  final VoidCallback onTap;
  final Color? titleColor;
  const _ActionTile(this.icon, this.color, this.title, this.subtitle,
      this.onTap, {this.titleColor});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: _iconBox(icon, color),
    title: Text(title,
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: titleColor)),
    subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    onTap: onTap,
  );
}
