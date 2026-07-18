import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/theme_service.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../home/bloc/home_cubit.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<HomeCubit>().refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        return Scaffold(
          backgroundColor: colors.bgPrimary,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => MobileShell.of(context)?.openDrawer(),
            ),
            title: const Text('Settings'),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.search_rounded),
                onPressed: () {
                  // Settings search logic
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            children: [
              _buildProfileCard(colors, state),
              const SizedBox(height: 32),
              _sectionLabel('QUOTA'),
              const SizedBox(height: 12),
              _buildQuotaCard(colors, state),
              const SizedBox(height: 32),
              _sectionLabel('STORAGE'),
              const SizedBox(height: 12),
              _buildStorageCard(colors, state),
              const SizedBox(height: 32),
              _sectionLabel('PREFERENCES'),
              const SizedBox(height: 12),
              _buildAppearanceCard(colors),
              const SizedBox(height: 16),
              _buildAboutCard(colors),
              const SizedBox(height: 32),
              _buildLogoutButton(colors),
              const SizedBox(height: 60),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuotaCard(AppColorsExtension colors, HomeState state) {
    final data = state.webShareQuota;
    
    if (data == null) {
      if (state.isLoading) {
         return const SizedBox(
              height: 80, child: Center(child: CircularProgressIndicator()));
      }
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Text('Web upload quota is currently unavailable.'),
      );
    }

    final remaining = data['remaining_gb']?.toString() ?? '...';
    final limit = data['limit_gb']?.toString() ?? '...';
    final usedPct = (data['used_bytes'] as num? ?? 0) /
        (data['limit_bytes'] as num? ?? 1);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: colors.bgSurface, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Web Upload Quota: $remaining GB of $limit GB remaining',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: usedPct.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: colors.bgSurfaceInset,
              valueColor:
                  AlwaysStoppedAnimation<Color>(colors.accentPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(AppColorsExtension colors, HomeState state) {
    final name = state.userName ?? 'User';
    final email = state.userEmail ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: colors.bgPrimary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(email,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white24),
        ],
      ),
    );
  }

  Widget _buildStorageCard(AppColorsExtension colors, HomeState state) {
    final usedMb = state.storageUsedMb;
    final usedText = usedMb >= 1024
        ? '${(usedMb / 1024).toStringAsFixed(1)} GB'
        : '${usedMb.toStringAsFixed(0)} MB';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_outlined, color: Colors.white, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$usedText of Unlimited used',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (usedMb / 102400).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: colors.bgSurfaceInset,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Icon(Icons.chevron_right_rounded, color: Colors.white24),
        ],
      ),
    );
  }

  Widget _buildAppearanceCard(AppColorsExtension colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.contrast_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 16),
              const Expanded(
                  child: Text('Appearance',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15))),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeService.instance.themeModeNotifier,
                builder: (context, mode, _) {
                  String modeText = mode == ThemeMode.system
                      ? 'System'
                      : (mode == ThemeMode.dark ? 'Dark' : 'Light');
                  return Row(
                    children: [
                      Text(modeText,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 13)),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white54, size: 18),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 44,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeService.instance.themeModeNotifier,
              builder: (context, currentMode, _) {
                return Row(
                  children: [
                    _buildThemeToggle(
                        ThemeMode.light, 'Light', currentMode, colors),
                    _buildThemeToggle(
                        ThemeMode.dark, 'Dark', currentMode, colors),
                    _buildThemeToggle(
                        ThemeMode.system, 'System', currentMode, colors),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeToggle(ThemeMode mode, String label, ThemeMode currentMode,
      AppColorsExtension colors) {
    final isSelected = currentMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => ThemeService.instance.setThemeMode(mode),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colors.accentPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAboutCard(AppColorsExtension colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.white, size: 24),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About App',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                SizedBox(height: 4),
                Text('v1.0.0',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Colors.white24),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(AppColorsExtension colors) {
    return GestureDetector(
      onTap: () => _logout(),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withAlpha(40)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: Colors.red, size: 22),
            SizedBox(width: 12),
            Text('Log Out',
                style: TextStyle(
                    color: Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white54,
              letterSpacing: 1.2),
        ),
      );

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log out?'),
        content: const Text('Your files are safely stored on Telegram.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
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
