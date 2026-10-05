/*
 * File: auto_backup_service.dart
 * Description: Orchestrator for auto-backup — rule bootstrap, asset scanning, ledger diffing, upload enqueue, and retention.
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import '../constants/app_constants.dart';
import '../models/backup_ledger_entry.dart';
import '../models/backup_rule.dart';
import '../models/file_record.dart';
import '../services/auto_backup_engine.dart';
import '../services/file_manager.dart';
import '../services/hive_service.dart';
import '../services/service_locator.dart';
import '../services/telegram_service.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import '../utils/device_hardware_service.dart';
import '../../features/upload/presentation/viewmodels/upload_task.dart';
import '../../features/upload/presentation/viewmodels/upload_view_model.dart';

/// Seam for testing: maps AssetEntity to BackupAsset without device I/O.
typedef AssetMapper = Future<BackupAsset> Function(AssetEntity entity);

/// Callback for enqueueing upload tasks to the upload pipeline.
typedef UploadEnqueuer = Future<void> Function(List<UploadTask> tasks);

/// Result of a backup run.
class BackupRunResult {
  final BackupPlan plan;
  final int uploadedCount;
  final List<String> errors;

  const BackupRunResult({
    required this.plan,
    required this.uploadedCount,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
  String get summary => 'Uploaded $uploadedCount, skipped ${plan.accountedTotal}, errors: ${errors.length}';
}

/// Internal class holding a scanned asset and its resolved local path.
class _ScannedAsset {
  final BackupAsset asset;
  final String? localPath;

  _ScannedAsset({required this.asset, this.localPath});
}

/// Orchestrates the auto-backup pipeline for a single rule.
class AutoBackupService {
  final HiveService _hive;
  final TelegramService _telegram;
  final FileManagerService _fileManager;
  final DeviceHardwareService _deviceHardware;

  AutoBackupService({
    required HiveService hive,
    required TelegramService telegram,
    required FileManagerService fileManager,
    required DeviceHardwareService deviceHardware,
  })  : _hive = hive,
        _telegram = telegram,
        _fileManager = fileManager,
        _deviceHardware = deviceHardware;

  /// Gets the backup rules box.
  Box<BackupRule> get _rulesBox => Hive.box<BackupRule>(AppConstants.backupRulesBox);

  /// Gets the backup ledger box.
  Box<BackupLedgerEntry> get _ledgerBox => Hive.box<BackupLedgerEntry>(AppConstants.backupLedgerBox);

  /// Ensures the Camera rule exists and is initialized with createdAt.
  /// Idempotent: safe to call multiple times.
  Future<BackupRule> bootstrapCameraRule() async {
    const cameraRuleId = 'camera';
    var rule = _rulesBox.get(cameraRuleId);

    if (rule == null) {
      rule = BackupRule(
        id: cameraRuleId,
        albumName: 'Camera',
        enabled: true,
        createdAt: DateTime.now(),
      );
      await _rulesBox.put(cameraRuleId, rule);
      AppLogger.i('Created default Camera backup rule', tag: 'AutoBackupService');
    } else if (rule.createdAt == null) {
      // Ensure createdAt is set for backfill gate (A2).
      rule = rule.copyWith(createdAt: DateTime.now());
      await rule.save();
      AppLogger.i('Set createdAt on existing Camera rule', tag: 'AutoBackupService');
    }

    return rule;
  }

  /// Loads ledger entries into maps keyed by assetId and lastKnownPath.
  Map<String, BackupLedgerEntry> loadLedgerByAssetId() {
    return {for (final e in _ledgerBox.values) e.assetId: e};
  }

  Map<String, BackupLedgerEntry> loadLedgerByPath() {
    return {for (final e in _ledgerBox.values if (e.lastKnownPath != null)) e.lastKnownPath!: e};
  }

  /// Loads cloud files in the album folder for reconciliation (A7).
  /// Converts sizeMb to bytes for comparison tolerance.
  Future<Map<String, CloudFileRef>> loadCloudFilesByName(String albumFolderId) async {
    final files = _hive.filesInFolder(albumFolderId);
    return {
      for (final f in files)
        f.name: CloudFileRef(
          fileId: f.fileId,
          sizeBytes: (f.sizeMb * 1048576).round(),
        ),
    };
  }

  /// Ensures the backup destination path exists: root/Backup/<Album>.
  /// Adopts existing folders if present, creates missing ones, caches IDs on the rule.
  Future<String> ensureBackupPath(BackupRule rule) async {
    String backupFolderId = rule.backupFolderId ?? '';
    String albumFolderId = rule.albumFolderId ?? '';

    // Resolve or create root/Backup
    if (backupFolderId.isEmpty) {
      final existing = _hive.allFolders.where((f) => f.name == 'Backup' && f.parentId == null).firstOrNull;
      if (existing != null) {
        backupFolderId = existing.id;
      } else {
        final newFolder = FolderRecord(
          id: 'backup_root_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Backup',
          parentId: null,
          createdAt: DateTime.now(),
        );
        await _hive.saveFolder(newFolder);
        await _fileManager.createFolder('Backup', folderId: newFolder.id);
        backupFolderId = newFolder.id;
      }
    }

    // Resolve or create root/Backup/<Album>
    if (albumFolderId.isEmpty) {
      final sanitizedAlbum = rule.albumName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final existing = _hive.allFolders.where((f) => f.name == sanitizedAlbum && f.parentId == backupFolderId).firstOrNull;
      if (existing != null) {
        albumFolderId = existing.id;
      } else {
        final newFolder = FolderRecord(
          id: 'backup_album_${DateTime.now().millisecondsSinceEpoch}',
          name: sanitizedAlbum,
          parentId: backupFolderId,
          createdAt: DateTime.now(),
        );
        await _hive.saveFolder(newFolder);
        await _fileManager.createFolder(sanitizedAlbum, parentId: backupFolderId, folderId: newFolder.id);
        albumFolderId = newFolder.id;
      }
    }

    // Cache IDs on rule
    if (rule.backupFolderId != backupFolderId || rule.albumFolderId != albumFolderId) {
      final updated = rule.copyWith(backupFolderId: backupFolderId, albumFolderId: albumFolderId);
      await updated.save();
    }

    // Verify folders still exist (D2: re-resolve on missing)
    if (!_hive.getFolder(backupFolderId).hasValue || !_hive.getFolder(albumFolderId).hasValue) {
      AppLogger.w('Cached backup folder missing, re-resolving', tag: 'AutoBackupService');
      return await ensureBackupPath(rule.copyWith(backupFolderId: null, albumFolderId: null));
    }

    return albumFolderId;
  }

  /// Scans device media for the rule's album and maps to BackupAsset with local paths.
  /// Uses pagination (60 per page) to bound memory.
  Future<List<_ScannedAsset>> scanAssets(
    BackupRule rule, {
    AssetMapper? mapper,
    int pageSize = 60,
  }) async {
    final permission = await DeviceMediaScanner.requestPermission();
    if (!permission) {
      throw Exception('Media permission denied');
    }

    final albums = await DeviceMediaScanner.loadAlbums();
    final targetAlbum = albums.where((a) => a.name == rule.albumName).firstOrNull;
    if (targetAlbum == null || targetAlbum.pathEntity == null) {
      throw Exception('Album "${rule.albumName}" not found on device');
    }

    final assets = <_ScannedAsset>[];
    int page = 0;
    bool hasMore = true;

    while (hasMore) {
      final entities = await DeviceMediaScanner.loadAlbumMedia(targetAlbum, page: page, pageSize: pageSize);
      if (entities.isEmpty) {
        hasMore = false;
        break;
      }

      for (final entity in entities) {
        try {
          final asset = mapper != null
              ? await mapper(entity)
              : await _defaultAssetMapper(entity);
          String? localPath;
          try {
            final pathResult = await DeviceMediaScanner.resolveUploadPath(entity);
            localPath = pathResult.$1;
          } catch (_) {}
          assets.add(_ScannedAsset(asset: asset, localPath: localPath));
        } catch (e) {
          AppLogger.w('Failed to map asset ${entity.id}: $e', tag: 'AutoBackupService');
        }
      }

      page++;
      if (entities.length < pageSize) hasMore = false;
    }

    return assets;
  }

  /// Default AssetMapper implementation using photo_manager metadata.
  Future<BackupAsset> _defaultAssetMapper(AssetEntity entity) async {
    final file = await entity.originFile;
    int sizeBytes = 0;
    int modifiedMs = DateTime.now().millisecondsSinceEpoch;

    if (file != null && await file.exists()) {
      final stat = await file.stat();
      sizeBytes = stat.size;
      modifiedMs = stat.modified.millisecondsSinceEpoch;
    } else {
      // Fallback: try to get size from entity metadata
      // Note: photo_manager doesn't expose size directly on AssetEntity in all versions
    }

    return BackupAsset(
      assetId: entity.id,
      title: entity.title ?? 'unknown',
      relativePath: entity.relativePath,
      modifiedMs: modifiedMs,
      sizeBytes: sizeBytes,
      isVideo: entity.type == AssetType.video,
    );
  }

  /// Executes retention: deletes oldest ledger-backed files beyond keepLast.
  Future<void> executeRetention(BackupRule rule, String albumFolderId) async {
    if (rule.retentionKeepLast <= 0) return;

    final folderFiles = _hive.filesInFolder(albumFolderId);
    final ledgerFileIds = _ledgerBox.values.map((e) => e.destFileId).where((id) => id != null).cast<String>().toSet();

    final toDelete = selectRetentionDeletions(
      folderFiles: folderFiles,
      keepLast: rule.retentionKeepLast,
      ledgerFileIds: ledgerFileIds,
    );

    for (final file in toDelete) {
      try {
        await _fileManager.deleteFile(file.fileId);
        AppLogger.i('Retention deleted: ${file.name}', tag: 'AutoBackupService');
      } catch (e) {
        AppLogger.e('Retention delete failed for ${file.fileId}: $e', tag: 'AutoBackupService');
      }
    }
  }

  /// Runs one complete backup cycle for the camera rule.
  Future<BackupRunResult> runBackup({
    AssetMapper? assetMapper,
    int maxItems = 200,
    int maxBytes = 2147483648, // 2 GiB
    UploadEnqueuer? enqueuer,
  }) async {
    final errors = <String>[];
    int uploadedCount = 0;
    final effectiveEnqueuer = enqueuer ?? _enqueuer;

    try {
      // 1. Bootstrap rule
      final rule = await bootstrapCameraRule();
      if (!rule.enabled) {
        return BackupRunResult(
          plan: const BackupPlan(uploads: [], adoptions: []),
          uploadedCount: 0,
          errors: ['Rule disabled'],
        );
      }

      // 2. Check eligibility
      final now = DateTime.now();
      final unmetered = await Connectivity.isUnmetered();
      final charging = await _deviceHardware.isCharging();
      // Permission checked during scan

      final eligibility = evaluateEligibility(
        rule: rule,
        now: now,
        unmetered: unmetered,
        charging: charging,
        permissionGranted: true, // Will fail in scan if not granted
      );

      if (!eligibility.isEligible) {
        return BackupRunResult(
          plan: const BackupPlan(uploads: [], adoptions: []),
          uploadedCount: 0,
          errors: [eligibility.label],
        );
      }

      // 3. Ensure destination folder
      final albumFolderId = await ensureBackupPath(rule);

      // 4. Load ledger and cloud files
      final ledgerByAssetId = loadLedgerByAssetId();
      final ledgerByPath = loadLedgerByPath();
      final cloudFilesByName = await loadCloudFilesByName(albumFolderId);

      // 5. Scan device assets
      final scannedAssets = await scanAssets(rule, mapper: assetMapper);
      final assets = scannedAssets.map((s) => s.asset).toList();

      // 6. Plan the run
      final plan = planRun(
        rule: rule,
        assets: assets,
        ledgerByAssetId: ledgerByAssetId,
        ledgerByPath: ledgerByPath,
        cloudFilesByName: cloudFilesByName,
        maxItems: maxItems,
        maxBytes: maxBytes,
      );

      // 7. Persist adoptions before upload (ledger repair)
      for (final adoption in plan.adoptions) {
        final entry = BackupLedgerEntry(
          assetId: adoption.key,
          fingerprint: adoption.fingerprint,
          lastKnownPath: adoption.lastKnownPath,
          destFileId: adoption.destFileId,
          destFolderId: albumFolderId,
          uploadedAt: DateTime.now(),
        );
        await _ledgerBox.put(adoption.key, entry);
      }

      // 8. Enqueue uploads with local paths
      if (plan.uploads.isNotEmpty && effectiveEnqueuer != null) {
        final tasks = <UploadTask>[];
        final pathMap = {for (final s in scannedAssets) s.asset.assetId: s.localPath};

        for (final item in plan.uploads) {
          final localPath = pathMap[item.asset.assetId];
          tasks.add(UploadTask(
            id: 'backup:${item.asset.assetId}:${item.asset.fingerprint}',
            name: item.destinationName,
            folderId: albumFolderId,
            path: localPath,
            size: item.asset.sizeBytes,
            isTemporaryCacheFile: false,
          ));
        }

        await effectiveEnqueuer(tasks);
        uploadedCount = tasks.length;
      }

      // 9. Execute retention
      await executeRetention(rule, albumFolderId);

      // 10. Update rule run metadata
      final updatedRule = rule.copyWith(
        lastRunAt: DateTime.now(),
        lastResult: errors.isEmpty ? 'completed' : 'partial_failure',
        lastUploadedCount: uploadedCount,
        backfillDone: true,
      );
      await updatedRule.save();

      return BackupRunResult(plan: plan, uploadedCount: uploadedCount, errors: errors);
    } catch (e, st) {
      AppLogger.e('Backup run failed: $e', tag: 'AutoBackupService', error: e, stackTrace: st);
      errors.add(e.toString());
      return BackupRunResult(
        plan: const BackupPlan(uploads: [], adoptions: []),
        uploadedCount: uploadedCount,
        errors: errors,
      );
    }
  }
}

/// BackupRule extension for copyWith
extension BackupRuleExtension on BackupRule {
  BackupRule copyWith({
    String? id,
    String? albumName,
    bool? enabled,
    bool? includePhotos,
    bool? includeVideos,
    bool? wifiOnly,
    bool? chargingOnly,
    int? windowStartMinutes,
    int? windowEndMinutes,
    bool? backfillDone,
    String? backupFolderId,
    String? albumFolderId,
    int? retentionKeepLast,
    DateTime? lastRunAt,
    String? lastResult,
    int? lastUploadedCount,
    DateTime? createdAt,
  }) {
    return BackupRule(
      id: id ?? this.id,
      albumName: albumName ?? this.albumName,
      enabled: enabled ?? this.enabled,
      includePhotos: includePhotos ?? this.includePhotos,
      includeVideos: includeVideos ?? this.includeVideos,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      chargingOnly: chargingOnly ?? this.chargingOnly,
      windowStartMinutes: windowStartMinutes ?? this.windowStartMinutes,
      windowEndMinutes: windowEndMinutes ?? this.windowEndMinutes,
      backfillDone: backfillDone ?? this.backfillDone,
      backupFolderId: backupFolderId ?? this.backupFolderId,
      albumFolderId: albumFolderId ?? this.albumFolderId,
      retentionKeepLast: retentionKeepLast ?? this.retentionKeepLast,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      lastResult: lastResult ?? this.lastResult,
      lastUploadedCount: lastUploadedCount ?? this.lastUploadedCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}