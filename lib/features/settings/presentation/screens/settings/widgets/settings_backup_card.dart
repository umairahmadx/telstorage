/*
 * File: settings_backup_card.dart
 * Description: Settings card exposing the auto-backup master switch, live
 * status line, destination copy, and navigation to the backup rule screen.
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/settings/presentation/screens/settings/backup/backup_screen.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';
import 'package:telstorage/core/services/device_media_scanner.dart';
import 'package:telstorage/core/utils/power_state.dart';

/// Card component rendering the auto-backup master switch and live status.
class SettingsBackupCard extends StatefulWidget {
  /// Optional permission checker used to read the current media access state.
  final Future<bool> Function()? permissionChecker;

  /// Optional network checker used to read the current unmetered state.
  final Future<bool> Function()? unmeteredChecker;

  /// Optional network checker used to read whether any route is available.
  final Future<bool> Function()? connectionChecker;

  /// Optional battery checker used to read the current charging state.
  final Future<bool> Function()? chargingChecker;

  /// Constructs SettingsBackupCard.
  const SettingsBackupCard({
    super.key,
    this.permissionChecker,
    this.unmeteredChecker,
    this.connectionChecker,
    this.chargingChecker,
  });

  @override
  State<SettingsBackupCard> createState() => _SettingsBackupCardState();
}

class _SettingsBackupCardState extends State<SettingsBackupCard>
    with WidgetsBindingObserver {
  Box<BackupRule>? _rulesBox;
  Future<String>? _statusFuture;
  String? _statusKey;
  Timer? _statusRefreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _statusRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshStatus(),
    );
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

  /// Builds a stable key so status checks refresh when rule state changes.
  String _statusKeyFor(BackupRule rule) => [
        rule.enabled,
        rule.wifiOnly,
        rule.chargingOnly,
        rule.windowStartMinutes,
        rule.windowEndMinutes,
        rule.lastResult,
        rule.lastUploadedCount,
      ].join('|');

  /// Reads the current eligibility state without prompting for permission.
  Future<String> _loadStatusLine(BackupRule rule) async {
    if (!rule.enabled) return 'Off';
    try {
      final permissionGranted = await (widget.permissionChecker ??
          DeviceMediaScanner.hasPermission)();
      final connected =
          await (widget.connectionChecker ?? Connectivity.hasConnection)();
      if (!connected) return 'Waiting for network';
      final unmetered = rule.wifiOnly
          ? await (widget.unmeteredChecker ?? Connectivity.isUnmetered)()
          : true;
      final charging = rule.chargingOnly
          ? await (widget.chargingChecker ?? PowerState.isCharging)()
          : true;
      final eligibility = evaluateEligibility(
        rule: rule,
        now: DateTime.now(),
        unmetered: unmetered,
        charging: charging,
        permissionGranted: permissionGranted,
      );
      if (!eligibility.isEligible) return eligibility.label;
      if (rule.lastResult == 'completed') {
        return 'Last run: ${rule.lastUploadedCount} item(s) backed up';
      }
      return eligibility.label;
    } catch (_) {
      return 'Backup status unavailable';
    }
  }

  Future<String> _statusLine(BackupRule rule) {
    final key = _statusKeyFor(rule);
    if (_statusFuture == null || _statusKey != key) {
      _statusKey = key;
      _statusFuture = _loadStatusLine(rule);
    }
    return _statusFuture!;
  }

  void _invalidateStatus() {
    _statusFuture = null;
    _statusKey = null;
  }

  void _refreshStatus() {
    if (!mounted) return;
    _invalidateStatus();
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggle(bool value) async {
    final rule = _rule;
    if (rule == null) return;
    rule.enabled = value;
    await rule.save();
    if (mounted) {
      _invalidateStatus();
      setState(() {});
    }
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
            if (mounted) {
              _invalidateStatus();
              setState(() {});
            }
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
                        FutureBuilder<String>(
                          future: _statusLine(rule),
                          initialData:
                              rule.enabled ? 'Checking backup status…' : 'Off',
                          builder: (context, snapshot) => Text(
                            snapshot.data ?? 'Checking backup status…',
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
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
