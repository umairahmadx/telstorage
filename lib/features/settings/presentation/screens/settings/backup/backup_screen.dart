/*
 * File: backup_screen.dart
 * Description: Auto-backup screen — source rules (Camera album, extra albums,
 * device folders with subfolders), toggles, daily window, retention, backfill,
 * live run progress, and destination copy.
 */

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/services/auto_backup_scheduler.dart';
import 'package:telstorage/core/services/auto_backup_types.dart';
import 'package:telstorage/core/services/device_media_scanner.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/core/utils/backup_permission_helper.dart';
import 'package:telstorage/core/utils/storage_permission_helper.dart';
import 'package:telstorage/shared/widgets/app_surface_card.dart';
import 'package:telstorage/shared/widgets/dialogs/app_dialogs.dart';

import 'backup_settings_cards.dart';

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

  Future<void> _toggleRule(BackupRule rule, bool value) async {
    rule.enabled = value;
    await rule.save();
    if (mounted) setState(() {});
    if (value && mounted) {
      final granted = await BackupPermissionHelper.promptForRule(context, rule);
      if (!granted && mounted) {
        _showSnack(rule.isDirectory
            ? 'Allow "All files access" so the folder can be backed up.'
            : 'Allow access to photos and videos to run the backup.');
      }
      if (mounted) setState(() {});
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _removeRule(BackupRule rule) async {
    final confirmed = await AppDialogs.showConfirm(
      context,
      title: 'Stop backing up "${rule.albumName}"?',
      message:
          'New files will no longer be backed up from this source. '
          'Files already backed up stay in TelStorage.',
      confirmText: 'Remove',
      cancelText: 'Cancel',
    );
    if (confirmed != true) return;
    await rule.delete();
    if (mounted) setState(() {});
  }

  Future<void> _addAlbum() async {
    final granted = await DeviceMediaScanner.requestPermission().catchError(
      (_) => true,
    );
    if (!granted || !mounted) {
      if (mounted) {
        _showSnack('Allow access to photos and videos to add an album.');
      }
      return;
    }
    final albums = await DeviceMediaScanner.loadAlbums();
    if (!mounted) return;
    final existing =
        _rulesBox?.values.map((r) => r.albumName.toLowerCase()).toSet() ?? {};
    final candidates = albums
        .where((a) =>
            !(a.pathEntity?.isAll ?? false) &&
            !existing.contains(a.name.toLowerCase()))
        .toList();
    if (candidates.isEmpty) {
      _showSnack('No more device albums available to add.');
      return;
    }
    final selected = await showModalBottomSheet<MediaAlbum>(
      context: context,
      backgroundColor: Theme.of(context).extension<AppColorsExtension>()!.bgSurface,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Add a device album',
                  style: TextStyle(
                      color: Theme.of(sheetContext)
                          .extension<AppColorsExtension>()!
                          .textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
            for (final album in candidates)
              ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: Text(album.name),
                subtitle: Text('${album.mediaCount} item(s)'),
                onTap: () => Navigator.of(sheetContext).pop(album),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final rule = BackupRule(
      id: 'album:${selected.name}',
      albumName: selected.name,
      enabled: true,
      createdAt: DateTime.now(),
    );
    await _rulesBox!.put(rule.id, rule);
    if (mounted) {
      await BackupPermissionHelper.promptForRule(context, rule);
      setState(() {});
    }
  }

  Future<void> _addFolder() async {
    final hasPermission =
        await StoragePermissionHelper.ensureStoragePermission(context);
    if (!hasPermission || !mounted) return;
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null || dirPath.isEmpty || !mounted) return;
    final normalized = p.normalize(dirPath).replaceAll('\\', '/');
    final id = 'dir:$normalized';
    if (_rulesBox?.get(id) != null) {
      _showSnack('This folder is already being backed up.');
      return;
    }
    final name = p.basename(normalized);
    final rule = BackupRule(
      id: id,
      albumName: name.isEmpty ? 'Folder' : name,
      enabled: true,
      createdAt: DateTime.now(),
      kind: 'directory',
      sourcePath: normalized,
      includeSubfolders: true,
    );
    await _rulesBox!.put(rule.id, rule);
    if (mounted) {
      await BackupPermissionHelper.promptForRule(context, rule);
      setState(() {});
    }
  }

  Future<void> _backupNow() async {
    if (_isBackingUp) return;
    final rules = _rulesBox?.values.where((r) => r.enabled).toList() ?? [];
    if (rules.isEmpty) return;
    setState(() => _isBackingUp = true);
    final isBackfill = rules.any((r) => !r.backfillDone);
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
        backgroundColor: (outcome.status == BackupRunStatus.ran && !outcome.needsRetry)
            ? Theme.of(context).extension<AppColorsExtension>()!.brandPrimary
            : null,
      ),
    );
  }

  String _outcomeMessage(BackupRunOutcome outcome) {
    final backfillPending =
        _rulesBox?.values.any((r) => r.enabled && !r.backfillDone) ?? false;
    switch (outcome.status) {
      case BackupRunStatus.ran:
        if (outcome.needsRetry && backfillPending) {
          return 'Backup batch completed with issues: ${outcome.label}. Tap again to retry.';
        }
        if (outcome.needsRetry) {
          return 'Some backup items need attention: ${outcome.label}. Tap again to retry.';
        }
        if (outcome.backfillComplete) {
          return 'Existing photos and videos have been backed up.';
        }
        if (backfillPending) {
          return 'Backup batch finished. Tap again to continue backing up existing media.';
        }
        return 'Backup started — continues in the background.';
      case BackupRunStatus.notDue:
        return 'Backup not due yet.';
      case BackupRunStatus.noRule:
        return 'No backup source enabled. Turn on Camera or add a folder first.';
      case BackupRunStatus.ineligible:
        if (outcome.label == 'Permission needed') {
          return 'Allow access to photos and videos to run the backup.';
        }
        if (outcome.label.contains('already running') ||
            outcome.label.contains('already in progress')) {
          return 'A backup is already running in the background.';
        }
        return 'Backup not eligible now (window, charging, or Wi‑Fi). '
            'Use "Back up now" to run immediately.';
      // BackupRunStatus has noAssets covered by 'ran' (uploads may be empty).
      case BackupRunStatus.failed:
        return 'Backup failed: ${outcome.label}.';
    }
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
          final extraRules =
              box.values.where((r) => r.id != 'camera').toList();
          final anyEnabled = box.values.any((r) => r.enabled);
          final backfillPending =
              box.values.any((r) => r.enabled && !r.backfillDone);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _masterCard(colors, rule),
              for (final extra in extraRules) ...[
                const SizedBox(height: 12),
                _sourceCard(colors, extra),
              ],
              const SizedBox(height: 12),
              _addSourcesCard(colors),
              const SizedBox(height: 16),
              if (rule.enabled) ...[
                BackupSettingsCards(rule: rule, onMutate: _mutate),
                const SizedBox(height: 24),
              ],
              _progressCard(colors),
              _backupNowButton(colors, anyEnabled, backfillPending),
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
            onChanged: (v) => _toggleRule(rule, v),
            activeThumbColor: colors.brandPrimary,
          ),
        ],
      ),
    );
  }

  Widget _sourceCard(AppColorsExtension colors, BackupRule rule) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: colors.borderSubtle,
      child: Row(
        children: [
          Icon(
            rule.isDirectory
                ? Icons.folder_outlined
                : Icons.photo_album_outlined,
            color: colors.textSecondary,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rule.albumName,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  rule.isDirectory
                      ? '${rule.sourcePath}${rule.mirrorsSubfolders ? ' · incl. subfolders' : ''}'
                      : 'Device album',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: colors.textTertiary,
            tooltip: 'Remove source',
            onPressed: () => _removeRule(rule),
          ),
          Switch(
            value: rule.enabled,
            onChanged: (v) => _toggleRule(rule, v),
            activeThumbColor: colors.brandPrimary,
          ),
        ],
      ),
    );
  }

  Widget _addSourcesCard(AppColorsExtension colors) {
    return AppSurfaceCard(
      padding: const EdgeInsets.all(6),
      borderColor: colors.borderSubtle,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.photo_album_outlined, color: colors.textPrimary),
            title: Text('Add device album',
                style: TextStyle(color: colors.textPrimary, fontSize: 14)),
            subtitle: Text('Screenshots, WhatsApp, Downloads…',
                style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            onTap: _addAlbum,
          ),
          ListTile(
            leading: Icon(Icons.create_new_folder_outlined,
                color: colors.textPrimary),
            title: Text('Add device folder',
                style: TextStyle(color: colors.textPrimary, fontSize: 14)),
            subtitle: Text('Any folder, subfolders kept as folder-in-folder',
                style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            onTap: _addFolder,
          ),
        ],
      ),
    );
  }

  Widget _progressCard(AppColorsExtension colors) {
    return ValueListenableBuilder<BackupRunProgress?>(
      valueListenable: AutoBackupScheduler.instance.runProgress,
      builder: (context, progress, _) {
        if (progress == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: AppSurfaceCard(
            padding: const EdgeInsets.all(18),
            borderColor: colors.borderSubtle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(progress.label,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: progress.scanning ? null : progress.fraction,
                  color: colors.brandPrimary,
                  backgroundColor: colors.bgSurfaceInset,
                ),
                if (progress.currentFileName != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    progress.currentFileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _backupNowButton(
    AppColorsExtension colors,
    bool anyEnabled,
    bool backfillPending,
  ) {
    return ElevatedButton(
      onPressed: anyEnabled && !_isBackingUp ? _backupNow : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.brandPrimary,
        foregroundColor: colors.bgPrimary,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Text(_isBackingUp
          ? 'Backup running…'
          : backfillPending
              ? 'Back up existing photos'
              : 'Back up now'),
    );
  }
}