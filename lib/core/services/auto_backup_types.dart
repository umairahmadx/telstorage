/*
 * File: auto_backup_types.dart
 * Description: Shared injectable hooks and result DTOs for auto-backup.
 */

import 'package:photo_manager/photo_manager.dart';

import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/shared/widgets/device_file_picker/device_media_scanner.dart';

/// Free-space probe in bytes; null means unknown and FAILS CLOSED (see E3).
/// A backup must never proceed when free space cannot be determined.
typedef FreeSpaceProvider = Future<int?> Function();

/// Permission prompt hook (F2). Defaults to DeviceMediaScanner.
typedef BackupRequestPermission = Future<bool> Function();

/// Album list hook. Defaults to DeviceMediaScanner.
typedef BackupLoadAlbums = Future<List<MediaAlbum>> Function();

/// Paged asset hook (60-asset pages bound RAM). Defaults to DeviceMediaScanner.
typedef BackupLoadPage = Future<List<AssetEntity>> Function(
  MediaAlbum album,
  int page,
  int pageSize,
);

/// Unmetered-network hook (C4). Defaults to Connectivity.isUnmetered.
typedef UnmeteredProvider = Future<bool> Function();

/// Charging-state hook (F1). Defaults to false — unknown → not charging
/// (fail-closed). Backed by `battery_plus` or marked "coming soon" in UI.
typedef PowerStateProvider = ChargingStateProvider;

/// Resolves a BackupAsset to an upload path plus temp-cache flag (F3).
/// Returns null when the device path cannot be resolved.
typedef BackupPathResolver = Future<({String path, bool isTemporary})?> Function(
    BackupAsset asset);
/// Posts the per-run summary notification body.
typedef BackupNotifier = Future<void> Function(String title, String body);

/// Registers / cancels the Workmanager periodic task by unique name.
typedef BackupScheduleAction = Future<void> Function(String uniqueName);

/// Idempotent `root/Backup/<Album>` destination ids.
class BackupPath {
  /// TelStorage id of the root `Backup` folder.
  final String backupFolderId;

  /// TelStorage id of the album child folder.
  final String albumFolderId;

  /// Constructs BackupPath.
  const BackupPath({required this.backupFolderId, required this.albumFolderId});
}

/// Scan outcome: the due-upload plan plus unresolvable-asset count.
class BackupCollectResult {
  /// Pure-engine plan (uploads ordered photos-first, oldest-first).
  final BackupPlan plan;

  /// Assets skipped because size/metadata could not be read.
  final int skippedUnresolvable;

  /// Constructs BackupCollectResult.
  const BackupCollectResult({required this.plan, this.skippedUnresolvable = 0});

  /// Assets due for upload (the plan's upload list).
  List<BackupUploadItem> get uploads => plan.uploads;
}

/// Terminal state of one consumeDueFlag run.
enum BackupRunStatus {
  /// Nothing to do — due flag not set and not a manual run.
  notDue,

  /// Rule failed the eligibility gates (window/Wi-Fi/charging).
  ineligible,

  /// No enabled rule exists.
  noRule,

  /// Scan, path setup, or enqueue failed.
  failed,

  /// Run completed (uploads enqueued, completions watermarked).
  ran,
}

/// Summary of one consumeDueFlag run for status lines and tests.
class BackupRunOutcome {
  /// Terminal run state.
  final BackupRunStatus status;

  /// Human-readable status line (eligibility label or run summary).
  final String label;

  /// Photos successfully uploaded this run.
  final int uploadedPhotos;

  /// Videos successfully uploaded this run.
  final int uploadedVideos;

  /// Assets skipped because they were unresolvable.
  final int skippedUnresolvable;

  /// Constructs BackupRunOutcome.
  const BackupRunOutcome({
    required this.status,
    required this.label,
    this.uploadedPhotos = 0,
    this.uploadedVideos = 0,
    this.skippedUnresolvable = 0,
  });
}

