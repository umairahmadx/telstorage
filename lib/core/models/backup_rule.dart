/*
 * File: backup_rule.dart
 * Description: Hive model describing one auto-backup rule (Camera album in v1) with schedule, network, retention, and destination-folder state.
 */

import 'package:hive/hive.dart';

part 'backup_rule.g.dart';

/// Hive local model for an auto-backup rule.
///
/// v1 supports a single Camera-album rule; the shape is generic so later
/// phases can add WhatsApp/custom folders without a schema migration.
@HiveType(typeId: 4)
class BackupRule extends HiveObject {
  /// Stable rule identifier (e.g. `camera`).
  @HiveField(0)
  String id;

  /// Device album display name this rule backs up (e.g. `Camera`).
  @HiveField(1)
  String albumName;

  /// Master switch for the rule.
  @HiveField(2)
  bool enabled;

  /// Whether photos are included.
  @HiveField(3)
  bool includePhotos;

  /// Whether videos are included.
  @HiveField(4)
  bool includeVideos;

  /// When true, runs only proceed on unmetered networks.
  @HiveField(5)
  bool wifiOnly;

  /// When true, runs only proceed while charging (advisory in v1, see F1).
  @HiveField(6)
  bool chargingOnly;

  /// Daily window start in minutes since local midnight (02:00 default).
  @HiveField(7)
  int windowStartMinutes;

  /// Daily window end in minutes since local midnight (05:00 default).
  @HiveField(8)
  int windowEndMinutes;

  /// Whether the one-time backfill of pre-existing assets completed.
  @HiveField(9)
  bool backfillDone;

  /// Cached TelStorage id of `root/Backup`; null until first resolved.
  @HiveField(10)
  String? backupFolderId;

  /// Cached TelStorage id of `root/Backup/<Album>`; null until resolved.
  @HiveField(11)
  String? albumFolderId;

  /// Keep-last-N retention inside the album folder; 0 keeps everything.
  @HiveField(12)
  int retentionKeepLast;

  /// When the last run finished; null when never run.
  @HiveField(13)
  DateTime? lastRunAt;

  /// Machine-readable outcome of the last run (e.g. `completed`, `skipped`).
  @HiveField(14)
  String? lastResult;

  /// Number of assets uploaded by the last run.
  @HiveField(15)
  int lastUploadedCount;

  /// When the rule was first created; assets older than this are skipped
  /// until a one-time backfill is requested (see A2).
  @HiveField(16)
  DateTime? createdAt;

  /// Constructs BackupRule.
  BackupRule({
    required this.id,
    required this.albumName,
    this.enabled = false,
    this.includePhotos = true,
    this.includeVideos = true,
    this.wifiOnly = true,
    this.chargingOnly = false,
    this.windowStartMinutes = 120,
    this.windowEndMinutes = 300,
    this.backfillDone = false,
    this.backupFolderId,
    this.albumFolderId,
    this.retentionKeepLast = 0,
    this.lastRunAt,
    this.lastResult,
    this.lastUploadedCount = 0,
    this.createdAt,
  });

  /// Whether [when] (local time) falls inside the rule's daily window.
  ///
  /// Handles windows spanning midnight (e.g. 23:00–02:00).
  bool isInWindow(DateTime when) {
    final minutes = when.hour * 60 + when.minute;
    if (windowStartMinutes <= windowEndMinutes) {
      return minutes >= windowStartMinutes && minutes < windowEndMinutes;
    }
    return minutes >= windowStartMinutes || minutes < windowEndMinutes;
  }
}
