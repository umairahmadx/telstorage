/*
 * File: settings_backup_card.dart
 * Description: Settings card exposing the auto-backup master switch, live
 * status line, destination copy, and navigation to the backup rule screen.
 */

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/settings/presentation/screens/settings/backup/backup_screen.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';

/// Card component rendering the auto-backup master switch and live status.
class SettingsBackupCard extends StatefulWidget {
  /// Constructs SettingsBackupCard.
  const SettingsBackupCard({super.key});

  @override
  State<SettingsBackupCard> createState() => _SettingsBackupCardState();
}

class _SettingsBackupCardState extends State<SettingsBackupCard> {
  Box<BackupRule>? _rulesBox;

  @override
  void initState() {
    super.initState();
    if (Hive.isBoxOpen(AppConstants.backupRulesBox)) {
      _rulesBox = Hive.box<BackupRule>(AppConstants.backupRulesBox);
      // Seed the default Camera rule so the card always has a rule to toggle.
      if (_rulesBox!.get('camera') == null) {
        _rulesBox!.put(
            'camera',
            BackupRule(
                id: 'camera', albumName: 'Camera', createdAt: DateTime.now()));
      }
    }
  }

  /// Reads the current rule snapshot from the box.
  BackupRule? get _rule => _rulesBox?.get('camera');

  /// Live status line for the card subtitle (plan Task 5 copy).
  String _statusLine(BackupRule rule) {
    if (!rule.enabled) return 'Off';
    if (rule.lastResult == 'completed') {
      return 'Last run: ${rule.lastUploadedCount} item(s) backed up';
    }
    final verdict = evaluateEligibility(
      rule: rule,
      now: DateTime.now(),
      unmetered: true,
      charging: true,
      permissionGranted: true,
    );
    return verdict.label;
  }

  Future<void> _toggle(bool value) async {
    final rule = _rule;
    if (rule == null) return;
    rule.enabled = value;
    await rule.save();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final rulesBox = _rulesBox;
    if (rulesBox == null) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return ValueListenableBuilder<Box<BackupRule>>(
      valueListenable: rulesBox.listenable(),
      builder: (context, box, _) {
        final rule = box.get('camera');
        if (rule == null) return const SizedBox.shrink();
        return AppSurfaceCard(
          onTap: () async {
            await Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => const BackupScreen()),
            );
            if (mounted) setState(() {});
          },
          padding: const EdgeInsets.all(18),
          borderColor: colors.borderSubtle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                    child: Icon(Icons.cloud_upload_outlined,
                        color: colors.textPrimary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto Backup',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _statusLine(rule),
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: rule.enabled,
                    onChanged: _toggle,
                    activeThumbColor: colors.brandPrimary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Backup to: root/Backup/Camera\n'
                'An existing root "Backup" folder is adopted, not duplicated.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
