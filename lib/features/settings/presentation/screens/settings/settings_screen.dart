/// File: settings_screen.dart
/// Description: Settings control center view providing profile info, storage usage, appearance options, and sign out.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:telstorage/core/routing/app_router.dart';
import 'package:telstorage/core/services/auth_service.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'package:telstorage/shared/widgets/mobile_shell.dart';
import 'widgets/settings_appearance_card.dart';
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
              _sectionLabel(colors, 'PREFERENCES'),
              const SizedBox(height: 10),
              const SettingsAppearanceCard(),
              const SizedBox(height: 24),
              _sectionLabel(colors, 'TOOLS & ABOUT'),
              const SizedBox(height: 10),
              const SettingsToolsCard(),
              const SizedBox(height: 32),
              _buildSignOutButton(colors),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  /// Builds section header caption.
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
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
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
          child: Padding(
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
          ),
        ),
      ),
    );
  }
}
