/*
 * File: backup_screen.dart
 * Description: Auto-backup rule screen — toggles, daily window, retention,
 * backfill, live status, and destination copy.
 */

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/services/auto_backup_scheduler.dart';
import 'package:telstorage/core/services/auto_backup_types.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  Box<BackupRule>? _rulesBox;
  bool _isBackingUp = false;

  @override
  void initState() {
    super.initState();
    if (Hive.isBoxOpen(AppConstants.backupRulesBox)) {
      _rulesBox = Hive.box<BackupRule>(AppConstants.backupRulesBox);
      if (_rulesBox!.get('camera') == null) {
        _rulesBox!.put(
            'camera',
            BackupRule(
                id: 'camera', albumName: 'Camera', createdAt: DateTime.now()));
      }
    }
  }

  BackupRule? get _rule => _rulesBox?.get('camera');

  Future<void> _mutate(void Function(BackupRule rule) change) async {
    final rule = _rule;
    if (rule == null) return;
    change(rule);
    await rule.save();
    if (mounted) setState(() {});
  }

  Future<void> _backupNow(BackupRule rule) async {
    if (_isBackingUp) return;
    setState(() => _isBackingUp = true);
    final isBackfill = !rule.backfillDone;
    final outcome = await AutoBackupScheduler.instance.consumeDueFlag(
      manual: true,
      backfill: isBackfill,
    );
    if (!mounted) return;
    setState(() => _isBackingUp = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_outcomeMessage(outcome)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: outcome.status == BackupRunStatus.ran
            ? Theme.of(context).extension<AppColorsExtension>()!.brandPrimary
            : null,
      ),
    );
  }

  String _outcomeMessage(BackupRunOutcome outcome) {
    switch (outcome.status) {
      case BackupRunStatus.ran:
        if (outcome.needsRetry && !(_rule?.backfillDone ?? true)) {
          return 'Backup batch finished. Tap again to continue backing up existing media.';
        }
        if (outcome.needsRetry) {
          return 'Some backup items need attention. Tap again to retry.';
        }
        if (outcome.backfillComplete) {
          return 'Existing photos and videos have been backed up.';
        }
        if (!(_rule?.backfillDone ?? true)) {
          return 'Backup batch finished. Tap again to continue backing up existing media.';
        }
        return 'Backup started — continues in the background.';
      case BackupRunStatus.notDue:
        return 'Backup not due yet.';
      case BackupRunStatus.noRule:
        return 'No backup rule enabled. Turn on Camera album backup first.';
      case BackupRunStatus.ineligible:
        if (outcome.label == 'Permission needed') {
          return 'Allow access to photos and videos to run the backup.';
        }
        return 'Backup not eligible now (window, charging, or Wi‑Fi). '
            'Use "Back up now" to run immediately.';
      // BackupRunStatus has noAssets covered by 'ran' (uploads may be empty).
      case BackupRunStatus.failed:
        return 'Backup failed: ${outcome.label}.';
    }
  }

  String _formatWindow(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final rulesBox = _rulesBox;
    if (rulesBox == null) {
      return Scaffold(
        backgroundColor: colors.bgPrimary,
        appBar: AppBar(
          backgroundColor: colors.bgPrimary,
          elevation: 0,
          title: const Text('Auto Backup'),
        ),
        body: const SizedBox.shrink(),
      );
    }

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        backgroundColor: colors.bgPrimary,
        elevation: 0,
        title: const Text('Auto Backup'),
      ),
      body: ValueListenableBuilder<Box<BackupRule>>(
        valueListenable: rulesBox.listenable(),
        builder: (context, box, _) {
          final rule = box.get('camera');
          if (rule == null) return const SizedBox.shrink();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _masterCard(colors, rule),
              const SizedBox(height: 16),
              if (rule.enabled) ...[
                _togglesCard(colors, rule),
                const SizedBox(height: 16),
                _windowCard(colors, rule),
                const SizedBox(height: 16),
                _retentionCard(colors, rule),
                const SizedBox(height: 16),
                _backfillCard(colors, rule),
                const SizedBox(height: 16),
                _destinationCard(colors),
                const SizedBox(height: 24),
              ],
              _backupNowButton(colors, rule),
            ],
          );
        },
      ),
    );
  }

  Widget _masterCard(AppColorsExtension colors, BackupRule rule) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Back up Camera album',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Photos & videos upload to TelStorage automatically.',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: rule.enabled,
            onChanged: (v) => _mutate((r) => r.enabled = v),
            activeThumbColor: colors.brandPrimary,
          ),
        ],
      ),
    );
  }

  Widget _togglesCard(AppColorsExtension colors, BackupRule rule) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(6),
      borderColor: colors.borderSubtle,
      child: Column(
        children: [
          _switchRow(colors, 'Photos', rule.includePhotos,
              (v) => _mutate((r) => r.includePhotos = v)),
          _switchRow(colors, 'Videos', rule.includeVideos,
              (v) => _mutate((r) => r.includeVideos = v)),
          _switchRow(colors, 'Wi-Fi only', rule.wifiOnly,
              (v) => _mutate((r) => r.wifiOnly = v)),
          _comingSoonRow(colors, 'Charging only', rule.chargingOnly),
        ],
      ),
    );
  }

  Widget _switchRow(
    AppColorsExtension colors,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: colors.brandPrimary,
      title: Text(title,
          style: TextStyle(color: colors.textPrimary, fontSize: 14)),
    );
  }

  Widget _comingSoonRow(
    AppColorsExtension colors,
    String title,
    bool value,
  ) {
    // F1: no charging-state API exists yet. Never ship a dead toggle.
    return SwitchListTile(
      value: value,
      onChanged: null,
      activeThumbColor: colors.brandPrimary,
      title: Text(title,
          style: TextStyle(color: colors.textPrimary, fontSize: 14)),
      subtitle: Text('Coming soon',
          style: TextStyle(color: colors.textTertiary, fontSize: 11)),
    );
  }

  Widget _windowCard(AppColorsExtension colors, BackupRule rule) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Daily window',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
              '${_formatWindow(rule.windowStartMinutes)} - ${_formatWindow(rule.windowEndMinutes)}',
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          RangeSlider(
            min: 0,
            max: 1440,
            divisions: 48,
            activeColor: colors.accentPrimary,
            values: RangeValues(
              rule.windowStartMinutes.toDouble(),
              rule.windowEndMinutes.toDouble(),
            ),
            onChanged: (values) => _mutate((r) {
              r.windowStartMinutes = values.start.round();
              r.windowEndMinutes = values.end.round();
            }),
          ),
        ],
      ),
    );
  }

  Widget _retentionCard(AppColorsExtension colors, BackupRule rule) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Retention',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            rule.retentionKeepLast == 0
                ? 'Keep all backups'
                : 'Keep the latest ${rule.retentionKeepLast} backed-up files',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: colors.textPrimary,
                onPressed: rule.retentionKeepLast > 0
                    ? () => _mutate(
                        (r) => r.retentionKeepLast = r.retentionKeepLast - 10)
                    : null,
              ),
              Text('${rule.retentionKeepLast}',
                  style: TextStyle(color: colors.textPrimary, fontSize: 14)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: colors.textPrimary,
                onPressed: () => _mutate(
                    (r) => r.retentionKeepLast = r.retentionKeepLast + 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _backfillCard(AppColorsExtension colors, BackupRule rule) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Existing media backfill',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            rule.backfillDone
                ? 'Existing photos have already been backed up.'
                : 'One-time upload of photos taken before enabling backup. '
                    'Large libraries upload slowly to avoid rate limits.',
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _destinationCard(AppColorsExtension colors) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Destination',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
              'root/Backup/Camera\n'
              'An existing root "Backup" folder is adopted, not duplicated.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Text('Deleting device photos never deletes backups.',
              style: TextStyle(color: colors.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _backupNowButton(AppColorsExtension colors, BackupRule rule) {
    return ElevatedButton(
      onPressed: rule.enabled && !_isBackingUp ? () => _backupNow(rule) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.brandPrimary,
        foregroundColor: colors.bgPrimary,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Text(_isBackingUp
          ? 'Preparing backup…'
          : rule.backfillDone
              ? 'Back up now'
              : 'Back up existing photos'),
    );
  }
}
