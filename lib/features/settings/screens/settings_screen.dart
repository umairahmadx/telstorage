import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/services/theme_service.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../shared/widgets/app_segmented_control.dart';
import '../../../shared/widgets/app_surface_card.dart';
import '../../home/bloc/home_cubit.dart';
import '../../sync/screens/sync_screen.dart';
import 'about_screen.dart';
import 'storage_details_screen.dart';

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
            backgroundColor: colors.bgPrimary,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.menu_rounded, color: colors.textPrimary),
              onPressed: () => MobileShell.of(context)?.openDrawer(),
            ),
            title: Text(
              'Control Center',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              _buildProfileCard(colors, state),
              const SizedBox(height: 24),
              _sectionLabel(colors, 'STORAGE & CLOUD'),
              const SizedBox(height: 10),
              _buildStorageCard(colors, state),
              const SizedBox(height: 24),
              _sectionLabel(colors, 'APPEARANCE'),
              const SizedBox(height: 10),
              _buildAppearanceCard(colors),
              const SizedBox(height: 24),
              _sectionLabel(colors, 'PREFERENCES & TOOLS'),
              const SizedBox(height: 10),
              _buildToolsCard(colors),
              const SizedBox(height: 32),
              _buildLogoutButton(colors),
              const SizedBox(height: 60),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(AppColorsExtension colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildProfileCard(AppColorsExtension colors, HomeState state) {
    final name = state.userName ?? 'User';
    final email = state.userEmail ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              shape: BoxShape.circle,
              border: Border.all(color: colors.accentPrimary.withValues(alpha: 0.3), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Connected to Telegram Cloud',
                    style: TextStyle(
                      color: colors.success,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageCard(AppColorsExtension colors, HomeState state) {
    final usedMb = state.storageUsedMb;
    final usedText = usedMb >= 1024
        ? '${(usedMb / 1024).toStringAsFixed(1)} GB'
        : '${usedMb.toStringAsFixed(0)} MB';

    return AppSurfaceCard(
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const StorageDetailsScreen()),
        );
      },
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.bgSurfaceInset,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.cloud_outlined, color: colors.textPrimary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Telegram Cloud Storage',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$usedText / Unlimited',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (usedMb / 102400).clamp(0.02, 1.0),
                      minHeight: 6,
                      backgroundColor: colors.bgSurfaceInset,
                      valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: colors.textTertiary, size: 20),
          ],
        ),
    );
  }

  Widget _buildAppearanceCard(AppColorsExtension colors) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.bgSurfaceInset,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.contrast_rounded, color: colors.textPrimary, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  'Theme Mode',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeService.instance.themeModeNotifier,
                builder: (context, mode, _) {
                  final modeText = mode == ThemeMode.system
                      ? 'System'
                      : (mode == ThemeMode.dark ? 'Dark' : 'Light');
                  return Text(
                    modeText,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                    Expanded(
                      child: AppSegmentedControl<ThemeMode>(
                        value: currentMode,
                        padding: EdgeInsets.zero,
                        height: 36,
                        radius: 8,
                        fontSize: 13,
                        segments: const [
                          AppSegment(value: ThemeMode.light, label: 'Light'),
                          AppSegment(value: ThemeMode.dark, label: 'Dark'),
                          AppSegment(value: ThemeMode.system, label: 'System'),
                        ],
                        onChanged: ThemeService.instance.setThemeMode,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsCard(AppColorsExtension colors) {
    return AppSurfaceCard(
      borderColor: colors.borderSubtle,
      child: Column(
        children: [
          _buildToolTile(
            colors,
            icon: AppIcons.syncing,
            title: 'Sync Center & Logs',
            subtitle: 'Real-time sync queue and activity logs',
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const SyncScreen()),
              );
            },
          ),
          Divider(color: colors.borderSubtle, height: 1),
          _buildToolTile(
            colors,
            icon: AppIcons.share,
            title: 'Public Web Shares',
            subtitle: 'Manage active storage.to shared links',
            onTap: () {
              MobileShell.of(context)?.switchTab(1);
            },
          ),
          Divider(color: colors.borderSubtle, height: 1),
          _buildToolTile(
            colors,
            icon: AppIcons.info,
            title: 'About TelStorage',
            subtitle: 'v1.0.0 — Telegram-powered Cloud Storage',
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToolTile(
    AppColorsExtension colors, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.bgSurfaceInset,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: colors.textPrimary, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 12,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: colors.textTertiary, size: 20),
    );
  }

  Widget _buildLogoutButton(AppColorsExtension colors) {
    return GestureDetector(
      onTap: () => _logout(colors),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, color: colors.error, size: 20),
            const SizedBox(width: 10),
            Text(
              'Log Out',
              style: TextStyle(
                color: colors.error,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout(AppColorsExtension colors) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Log out?', style: TextStyle(color: colors.textPrimary)),
        content: Text('Your files are safely stored on Telegram.',
            style: TextStyle(color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Log out', style: TextStyle(color: colors.textPrimary)),
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
