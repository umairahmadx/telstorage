/*
 * File: settings_tools_card.dart
 * Description: Widget listing tool shortcuts including Sync Center, Web Shares, and About page with precise directional ripple shapes.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/theme/app_icons.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/core/utils/battery_optimization_helper.dart';
import 'package:telstorage/features/settings/presentation/screens/about/about_screen.dart';
import 'package:telstorage/features/settings/presentation/screens/error_logs/error_logs_screen.dart';
import 'package:telstorage/features/sync/presentation/screens/sync/sync_screen.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';
import 'package:telstorage/shared/widgets/mobile_shell.dart';

/// Card component presenting operational tools, diagnostics, and battery management.
class SettingsToolsCard extends StatefulWidget {
  /// Constructs SettingsToolsCard.
  const SettingsToolsCard({super.key});

  @override
  State<SettingsToolsCard> createState() => _SettingsToolsCardState();
}

class _SettingsToolsCardState extends State<SettingsToolsCard> {
  bool _isBatteryExempt = true;

  @override
  void initState() {
    super.initState();
    _checkBatteryStatus();
  }

  Future<void> _checkBatteryStatus() async {
    final exempt = await BatteryOptimizationHelper.isOptimizationDisabled();
    if (mounted) {
      setState(() => _isBatteryExempt = exempt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return AppSurfaceCard(
      borderRadius: BorderRadius.circular(16),
      borderColor: colors.borderSubtle,
      child: Column(
        children: [
          _buildToolTile(
            colors,
            icon: AppIcons.syncing,
            title: 'Sync Center & Logs',
            subtitle: 'Real-time sync queue and activity logs',
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const SyncScreen()),
              );
            },
          ),
          Divider(color: colors.borderSubtle, height: 1),
          _buildToolTile(
            colors,
            icon: Icons.bug_report_rounded,
            title: 'Error & Diagnostic Logs',
            subtitle: 'Inspect system warnings, network logs, and errors',
            borderRadius: BorderRadius.zero,
            onTap: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const ErrorLogsScreen()),
              );
            },
          ),
          Divider(color: colors.borderSubtle, height: 1),
          _buildToolTile(
            colors,
            icon: AppIcons.share,
            title: 'Public Web Shares',
            subtitle: 'Manage active storage.to shared links',
            borderRadius: BorderRadius.zero,
            onTap: () {
              MobileShell.of(context)?.switchTab(1);
            },
          ),

          Divider(color: colors.borderSubtle, height: 1),
          _buildToolTile(
            colors,
            icon: Icons.battery_charging_full_rounded,
            title: 'Background Upload & Battery',
            subtitle: _isBatteryExempt
                ? 'Unrestricted (optimized for background)'
                : 'Restricted — tap to enable for large transfers',
            trailing: Icon(
              _isBatteryExempt
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              color: _isBatteryExempt ? colors.success : colors.warning,
              size: 20,
            ),
            borderRadius: BorderRadius.zero,
            onTap: () async {
              if (_isBatteryExempt) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Unrestricted background execution is already active.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                return;
              }

              final granted =
                  await BatteryOptimizationHelper.requestOptimizationDisabled();
              await _checkBatteryStatus();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      granted
                          ? 'Background battery optimization disabled.'
                          : 'Battery optimization is still active.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          Divider(color: colors.borderSubtle, height: 1),
          _buildToolTile(
            colors,
            icon: AppIcons.info,
            title: 'About TelStorage',
            subtitle: 'v1.2.0 — Telegram-powered Cloud Storage',
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(16)),
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

  /// Builds individual tool navigation row with directional border radius.
  Widget _buildToolTile(
    AppColorsExtension colors, {
    required IconData icon,
    required String title,
    required String subtitle,
    required BorderRadius borderRadius,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
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
      trailing: trailing ??
          Icon(Icons.chevron_right_rounded,
              color: colors.textTertiary, size: 20),
    );
  }
}
