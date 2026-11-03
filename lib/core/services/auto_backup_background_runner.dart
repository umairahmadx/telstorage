/*
 * File: auto_backup_background_runner.dart
 * Description: Android background-isolate auto-backup execution using the
 * WorkManager foreground-worker pipeline.
 */

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/models/download_job.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/pending_action.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/services/auto_backup_service.dart';
import 'package:telstorage/core/services/auto_backup_types.dart';
import 'package:telstorage/core/services/error_log_service.dart';
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/metadata_sync_coordinator.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/upload_service.dart';
import 'package:telstorage/core/utils/app_logger.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/core/services/device_media_scanner.dart';

/// Executes a scheduled backup without the UI isolate or UploadBloc.
class AutoBackupBackgroundRunner {
  /// Service that scans media, resolves folders, and persists the ledger.
  final AutoBackupService _backup;

  /// Upload pipeline rebuilt inside the background isolate.
  final UploadService _uploads;

  /// Backup rules persisted for the logged-in account.
  final Box<BackupRule> _rules;

  /// Shared due-state box used by the foreground and background workers.
  final Box<bool> _state;

  /// Resolves a device asset into an uploadable path.
  final BackupPathResolver _resolvePath;

  /// Constructs an injectable background runner.
  AutoBackupBackgroundRunner({
    required AutoBackupService backup,
    required UploadService uploads,
    required Box<BackupRule> rules,
    required Box<bool> state,
    BackupPathResolver? resolvePath,
  })  : _backup = backup,
        _uploads = uploads,
        _rules = rules,
        _state = state,
        _resolvePath = resolvePath ?? _resolveAssetPath;

  /// Builds production dependencies and runs one scheduled background pass.
  static Future<BackupRunOutcome> runProduction({
    DateTime? now,
    Future<String?> Function(String key)? readCredential,
  }) async {
    const storage = FlutterSecureStorage();
    final read = readCredential ?? storage.read;
    final token = await read(AppConstants.keyBotToken);
    final channelId = await read(AppConstants.keyChannelId);
    if (token == null || channelId == null) {
      return const BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: 'Background backup credentials unavailable',
      );
    }

    await _openBackgroundBoxes();
    await ErrorLogService.instance.init();

    final telegram = TelegramService();
    await telegram.init(token, channelId);
    final hive = HiveService.instance;
    final metadata = MetadataService(telegram);
    final coordinator =
        MetadataSyncCoordinator(metadata, metadata.partitionService);
    final files = FileManagerService(metadata, telegram, hive, coordinator);
    final backup = AutoBackupService(
      hive: hive,
      fileManager: files,
      isUnmetered: Connectivity.isUnmetered,
      freeSpaceBytes: () async {
        final free = await DiskSpacePlus().getFreeDiskSpace;
        return free?.toInt();
      },
    );
    final uploads = UploadService(telegram, metadata, hive);
    final rules = Hive.box<BackupRule>(AppConstants.backupRulesBox);
    final state = Hive.box<bool>(AppConstants.autoBackupStateBox);

    return AutoBackupBackgroundRunner(
      backup: backup,
      uploads: uploads,
      rules: rules,
      state: state,
    ).run(now: now);
  }

  /// Opens every local box required by the background upload pipeline.
  static Future<void> _openBackgroundBoxes() async {
    await HiveService.openBoxDefensively<FileRecord>(AppConstants.filesBox);
    await HiveService.openBoxDefensively<FolderRecord>(AppConstants.foldersBox);
    await HiveService.openBoxDefensively<DownloadJob>(
      AppConstants.downloadsBox,
    );
    await HiveService.openBoxDefensively<PendingAction>(
      AppConstants.pendingActionsBox,
      preserveQuarantine: true,
    );
    await HiveService.openBoxDefensively(AppConstants.webSharesBox);
    await HiveService.openBoxDefensively(AppConstants.uploadChunksBox);
    await HiveService.openBoxDefensively<int>(AppConstants.partitionSyncBox);
    await HiveService.openBoxDefensively<BackupRule>(
      AppConstants.backupRulesBox,
    );
    await HiveService.openBoxDefensively<BackupLedgerEntry>(
      AppConstants.backupLedgerBox,
    );
    await HiveService.openBoxDefensively<bool>(
      AppConstants.autoBackupStateBox,
    );
    await HiveService.openBoxDefensively(AppConstants.errorLogsBox);
  }

  /// Runs one due scheduled pass and leaves the due flag armed on failure.
  Future<BackupRunOutcome> run({DateTime? now}) async {
    final due =
        _state.get(AppConstants.autoBackupDueKey, defaultValue: false) ?? false;
    if (!due) {
      return const BackupRunOutcome(
        status: BackupRunStatus.notDue,
        label: 'Not due',
      );
    }

    final rule = _firstEnabledRule();
    if (rule == null) {
      return const BackupRunOutcome(
        status: BackupRunStatus.noRule,
        label: 'Off',
      );
    }

    final eligibility = await _backup.isEligibleNow(rule, now: now);
    if (eligibility.isFailure) {
      return BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: eligibility.failureOrNull?.message ?? 'Eligibility failed',
      );
    }
    final verdict = eligibility.dataOrNull!;
    if (!verdict.isEligible) {
      return BackupRunOutcome(
        status: BackupRunStatus.ineligible,
        label: verdict.label,
      );
    }

    final collected = await _backup.collectDueAssets(rule);
    if (collected.isFailure) {
      return BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: collected.failureOrNull?.message ?? 'Scan failed',
      );
    }
    final result = collected.dataOrNull!;
    if (result.uploads.isEmpty) {
      if (result.skippedUnresolvable == 0 && !result.plan.capped) {
        await _state.put(AppConstants.autoBackupDueKey, false);
      }
      return BackupRunOutcome(
        status: BackupRunStatus.ran,
        label: 'Already up to date',
        skippedUnresolvable: result.skippedUnresolvable,
        needsRetry: result.plan.capped || result.skippedUnresolvable > 0,
      );
    }

    final pathResult = await _backup.ensureBackupPath(
      rule.albumName,
      rule: rule,
    );
    if (pathResult.isFailure) {
      return BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: pathResult.failureOrNull?.message ?? 'Path setup failed',
      );
    }
    final albumFolderId = pathResult.dataOrNull!.albumFolderId;
    final freeSpace = await _backup.ensureFreeSpaceFor(
      result.uploads.map((upload) => upload.asset).toList(),
    );
    if (freeSpace.isFailure) {
      return BackupRunOutcome(
        status: BackupRunStatus.failed,
        label: freeSpace.failureOrNull?.message ?? 'Low storage',
      );
    }

    final completed = <BackupUploadItem>[];
    final destinationIds = <String, String>{};
    final metadataBatch = <Map<String, dynamic>>[];
    var failed = 0;
    var unresolved = result.skippedUnresolvable;
    var photos = 0;
    var videos = 0;

    for (final upload in result.uploads) {
      final resolved = await _resolvePath(upload.asset);
      if (resolved == null) {
        unresolved++;
        continue;
      }
      final taskId =
          'backup:${upload.asset.assetId}:${upload.asset.fingerprint}';
      final outcome = await _uploads.uploadFile(
        null,
        upload.destinationName,
        albumFolderId,
        (_, __) {},
        filePath: resolved.path,
        fileLength: upload.asset.sizeBytes,
        skipGlobalMetadataUpdate: true,
        taskId: taskId,
      );
      if (outcome.isFailure) {
        failed++;
        AppLogger.e(
          'Background backup upload failed for ${upload.asset.assetId}: '
          '${outcome.failureOrNull?.message ?? 'Upload failed'}',
          tag: 'AutoBackup',
        );
        continue;
      }

      final fileMeta = outcome.dataOrNull!;
      final destinationId = fileMeta['metadata_file_id'] as String?;
      if (destinationId == null || destinationId.isEmpty) {
        failed++;
        AppLogger.e(
          'Background backup upload returned no destination id for '
          '${upload.asset.assetId}',
          tag: 'AutoBackup',
        );
        continue;
      }
      completed.add(upload);
      destinationIds[upload.asset.assetId] = destinationId;
      metadataBatch.add(fileMeta);
      if (upload.asset.isVideo) {
        videos++;
      } else {
        photos++;
      }
    }

    if (metadataBatch.isNotEmpty) {
      try {
        await _uploads.commitUploadBatch(metadataBatch);
      } catch (e, st) {
        AppLogger.e(
          'Background backup metadata commit failed: $e',
          tag: 'AutoBackup',
          error: e,
          stackTrace: st,
        );
        failed += completed.length;
        completed.clear();
        destinationIds.clear();
      }
    }

    var watermarkFailed = false;
    if (completed.isNotEmpty) {
      final watermark = await _backup.advanceWatermark(
        rule: rule,
        uploads: completed,
        destFileIdsByAssetId: destinationIds,
        destFolderId: albumFolderId,
      );
      watermarkFailed = watermark.isFailure;
    }
    await _backup.enforceRetention(rule);

    final needsRetry =
        failed > 0 || unresolved > 0 || result.plan.capped || watermarkFailed;
    if (!needsRetry) {
      await _state.put(AppConstants.autoBackupDueKey, false);
    }
    return BackupRunOutcome(
      status: BackupRunStatus.ran,
      label: 'Backed up $photos photos, $videos videos',
      uploadedPhotos: photos,
      uploadedVideos: videos,
      skippedUnresolvable: unresolved,
      needsRetry: needsRetry,
    );
  }

  /// Returns the first enabled backup rule, if any.
  BackupRule? _firstEnabledRule() {
    for (final rule in _rules.values) {
      if (rule.enabled) return rule;
    }
    return null;
  }

  /// Resolves a MediaStore asset to a native or temporary upload path.
  static Future<({String path, bool isTemporary})?> _resolveAssetPath(
    BackupAsset asset,
  ) async {
    try {
      final entity = await AssetEntity.fromId(asset.assetId);
      if (entity == null) return null;
      final resolved = await DeviceMediaScanner.resolveUploadPath(entity);
      return (path: resolved.$1, isTemporary: resolved.$2);
    } catch (e) {
      AppLogger.w(
        'Background backup path resolve failed ${asset.assetId}: $e',
        tag: 'AutoBackup',
      );
      return null;
    }
  }
}
