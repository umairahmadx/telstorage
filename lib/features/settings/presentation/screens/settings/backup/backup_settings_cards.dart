/*
 * File: backup_settings_cards.dart
 * Description: Per-rule backup settings cards (media toggles, daily window,
 * retention, backfill status, destination copy) extracted from BackupScreen
 * to keep the screen within the 500-line file limit.
 */

import 'package:flutter/material.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';

/// Settings cards bound to one backup rule; mutations go through [onMutate].
class BackupSettingsCards extends StatelessWidget {
  /// Constructs BackupSettingsCards.
  const BackupSettingsCards({
    super.key,
    required this.rule,
    required this.onMutate,
  });

  /// The rule whose settings are displayed and edited.
  final BackupRule rule;

  /// Applies and persists a rule mutation, then refreshes the parent.
  final Future<void> Function(void Function(BackupRule rule) change) onMutate;

  String _formatWindow(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Column(
      children: [
        _togglesCard(colors),
        const SizedBox(height: 16),
        _windowCard(colors),
        const SizedBox(height: 16),
        _retentionCard(colors),
        const SizedBox(height: 16),
        _backfillCard(colors),
        const SizedBox(height: 16),
        _destinationCard(colors),
      ],
    );
  }

  Widget _togglesCard(AppColorsExtension colors) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(6),
      borderColor: colors.borderSubtle,
      child: Column(
        children: [
          _switchRow(colors, 'Photos', rule.includePhotos,
              (v) => onMutate((r) => r.includePhotos = v)),
          _switchRow(colors, 'Videos', rule.includeVideos,
              (v) => onMutate((r) => r.includeVideos = v)),
          _switchRow(colors, 'Wi-Fi only', rule.wifiOnly,
              (v) => onMutate((r) => r.wifiOnly = v)),
          _switchRow(colors, 'Charging only', rule.chargingOnly,
              (v) => onMutate((r) => r.chargingOnly = v)),
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

  Widget _windowCard(AppColorsExtension colors) {
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
            onChanged: (values) => onMutate((r) {
              r.windowStartMinutes = values.start.round();
              r.windowEndMinutes = values.end.round();
            }),
          ),
        ],
      ),
    );
  }

  Widget _retentionCard(AppColorsExtension colors) {
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
                    ? () => onMutate(
                        (r) => r.retentionKeepLast = r.retentionKeepLast - 10)
                    : null,
              ),
              Text('${rule.retentionKeepLast}',
                  style: TextStyle(color: colors.textPrimary, fontSize: 14)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: colors.textPrimary,
                onPressed: () => onMutate(
                    (r) => r.retentionKeepLast = r.retentionKeepLast + 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _backfillCard(AppColorsExtension colors) {
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
              'root/Backup/Camera — each added album or folder gets its own '
              'subfolder under root/Backup, mirroring subfolders inside it.\n'
              'An existing root "Backup" folder is adopted, not duplicated.',
              style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Text('Deleting device photos never deletes backups.',
              style: TextStyle(color: colors.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }
}