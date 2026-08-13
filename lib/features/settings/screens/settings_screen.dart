import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../home/bloc/home_cubit.dart';
import 'widgets/settings_appearance_card.dart';
import 'widgets/settings_profile_card.dart';
import 'widgets/settings_storage_card.dart';
import 'widgets/settings_tools_card.dart';

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
              SettingsProfileCard(state: state),
              const SizedBox(height: 24),
              _sectionLabel(colors, 'STORAGE & CLOUD'),
              const SizedBox(height: 10),
              SettingsStorageCard(state: state),
              const SizedBox(height: 24),
              _sectionLabel(colors, 'APPEARANCE'),
              const SizedBox(height: 10),
              const SettingsAppearanceCard(),
              const SizedBox(height: 24),
              _sectionLabel(colors, 'PREFERENCES & TOOLS'),
              const SizedBox(height: 10),
              const SettingsToolsCard(),
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
