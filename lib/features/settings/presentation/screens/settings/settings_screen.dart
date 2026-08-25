/*
 * File: settings_screen.dart
 * Description: Settings control center view providing profile info, storage usage, appearance options, and sign out.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/routing/app_router.dart';
import 'package:telstorage/core/services/auth_service.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';
import 'package:telstorage/shared/widgets/mobile_shell.dart';
import 'widgets/settings_appearance_card.dart';
import 'widgets/settings_cache_card.dart';
import 'widgets/settings_profile_card.dart';
import 'widgets/settings_storage_card.dart';
import 'widgets/settings_tools_card.dart';

/// Screen component rendering app settings and control center.
class SettingsScreen extends StatefulWidget {
  /// Constructs SettingsScreen.
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// State controller for SettingsScreen.
class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      body: BlocBuilder<HomeCubit, HomeState>(
        builder: (context, state) {
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: colors.bgPrimary,
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => MobileShell.of(context)?.openDrawer(),
                ),
                title: const Text('Settings'),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Profile Header Card
                    SettingsProfileCard(state: state),
                    const SizedBox(height: 24),

                    // Storage Overview Card
                    _sectionLabel(colors, 'STORAGE'),
                    const SizedBox(height: 8),
                    SettingsStorageCard(state: state),
                    const SizedBox(height: 24),

                    // Cache & Data Management Card
                    _sectionLabel(colors, 'CACHE & DATA'),
                    const SizedBox(height: 8),
                    const SettingsCacheCard(),
                    const SizedBox(height: 24),

                    // Tools & Utilities Card
                    _sectionLabel(colors, 'TOOLS & ABOUT'),
                    const SizedBox(height: 8),
                    const SettingsToolsCard(),
                    const SizedBox(height: 24),

                    // Appearance & Theme Card
                    _sectionLabel(colors, 'APPEARANCE'),
                    const SizedBox(height: 8),
                    const SettingsAppearanceCard(),
                    const SizedBox(height: 32),

                    // Sign Out Button
                    _buildSignOutButton(colors),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(AppColorsExtension colors, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          color: colors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  /// Builds sign out button card.
  Widget _buildSignOutButton(AppColorsExtension colors) {
    return AppSurfaceCard(
      color: colors.bgSurface,
      radius: 16,
      borderColor: colors.borderSubtle,
      onTap: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: colors.bgSurface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text(
              'Sign Out',
              style: TextStyle(
                  color: colors.textPrimary, fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Are you sure you want to sign out? Your offline cache will remain safe.',
              style: TextStyle(color: colors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: TextStyle(color: colors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.error,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Sign Out',
                    style: TextStyle(color: colors.bgPrimary)),
              ),
            ],
          ),
        );

        if (confirm == true && mounted) {
          await AuthService.instance.logout();
          if (mounted) {
            Navigator.of(context, rootNavigator: true)
                .pushNamedAndRemoveUntil(
                    AppRouter.login, (route) => false);
          }
        }
      },
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.logout_rounded, color: colors.error, size: 20),
          const SizedBox(width: 8),
          Text(
            'Sign Out',
            style: TextStyle(
              color: colors.error,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
