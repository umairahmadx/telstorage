/*
 * File: auto_backup_engine.dart
 * Description: Pure, side-effect-free auto-backup logic covering eligibility, ledger diffing, destination naming, and retention selection.
 */

import '../models/backup_ledger_entry.dart';
import '../models/backup_rule.dart';
import '../models/file_record.dart';

/// Size tolerance for cloud reconciliation: 0.01 MB (10485 bytes),
/// mirroring the UploadService duplicate-detection threshold.
const int _reconcileToleranceBytes = 10485;

/// Minimal device-asset descriptor decoupled from photo_manager types so the
/// engine stays unit-testable without a device.
class BackupAsset {
  /// MediaStore asset identifier.
  final String assetId;

  /// Display file name (e.g. `IMG_0001.jpg`).
  final String title;

  /// Album-relative folder path ending with `/`, when known.
  final String? relativePath;

  /// Last-modified timestamp in milliseconds since epoch.
  final int modifiedMs;

  /// File size in bytes.
  final int sizeBytes;

  /// Whether this asset is a video.
  final bool isVideo;

  /// Constructs BackupAsset.
  const BackupAsset({
    required this.assetId,
    required this.title,
    this.relativePath,
    required this.modifiedMs,
    required this.sizeBytes,
    required this.isVideo,
  });

  /// Stable content fingerprint (no file read).
  String get fingerprint => BackupLedgerEntry.fingerprintFor(
        modifiedMs: modifiedMs,
        sizeBytes: sizeBytes,
      );

  /// Device path used for MediaStore-id fallback matching (see B1).
  String get containerPath => relativePath == null ? title : '$relativePath$title';
}
/// Why a rule can or cannot run right now.
enum BackupBlockReason {
  ready,
  disabled,
  permissionDenied,
  outsideWindow,
  metered,
  notCharging,
}

/// Eligibility verdict for a rule at a point in time.
class BackupEligibility {
  /// Machine-readable block reason.
  final BackupBlockReason reason;

  /// Constructs BackupEligibility.
  const BackupEligibility(this.reason);

  /// Whether the rule may run now.
  bool get isEligible => reason == BackupBlockReason.ready;

  /// Human-readable status line for the Settings card (Task 5 copy).
  String get label => switch (reason) {
        BackupBlockReason.ready => 'Ready',
        BackupBlockReason.disabled => 'Off',
        BackupBlockReason.permissionDenied => 'Permission needed',
        BackupBlockReason.outsideWindow => 'Pending — will run when eligible',
        BackupBlockReason.metered => 'Waiting for unmetered network',
        BackupBlockReason.notCharging => 'Waiting for charger',
      };
}

/// Evaluates whether [rule] may run, in precedence order (disabled → permission
/// → window → unmetered → charging). See edge cases F1, F2 and C7.
BackupEligibility evaluateEligibility({
  required BackupRule rule,
  required DateTime now,
  required bool unmetered,
  required bool charging,
  required bool permissionGranted,
}) {
  if (!rule.enabled) {
    return const BackupEligibility(BackupBlockReason.disabled);
  }
  if (!permissionGranted) {
    return const BackupEligibility(BackupBlockReason.permissionDenied);
  }
  if (!rule.isInWindow(now)) {
    return const BackupEligibility(BackupBlockReason.outsideWindow);
  }
  if (rule.wifiOnly && !unmetered) {
    return const BackupEligibility(BackupBlockReason.metered);
  }
  if (rule.chargingOnly && !charging) {
    return const BackupEligibility(BackupBlockReason.notCharging);
  }
  return const BackupEligibility(BackupBlockReason.ready);
}
/// One asset scheduled for upload in the next run.
class BackupUploadItem {
  /// Source asset descriptor.
  final BackupAsset asset;

  /// Unique destination file name, collision-suffixed when needed (A8).
  final String destinationName;

  /// Previous cloud file id to replace for edited assets (A3), else null.
  final String? replacesFileId;

  /// Constructs BackupUploadItem.
  const BackupUploadItem({
    required this.asset,
    required this.destinationName,
    this.replacesFileId,
  });
}

/// Ledger repair emitted by the engine for the service layer to persist.
class BackupAdoption {
  /// Ledger key to write.
  final String key;

  /// Fingerprint to store for [key].
  final String fingerprint;

  /// Ledger key to remove when the identity was migrated, else null.
  final String? replacedKey;

  /// Device path to remember for MediaStore-id fallback (B1).
  final String? lastKnownPath;

  /// Cloud file id backing the adoption, when reconciliation matched (A7).
  final String? destFileId;

  /// Constructs BackupAdoption.
  const BackupAdoption({
    required this.key,
    required this.fingerprint,
    this.replacedKey,
    this.lastKnownPath,
    this.destFileId,
  });
}

/// Outcome of planning one run.
class BackupPlan {
  /// Assets scheduled for upload, ordered photos-then-videos, oldest first.
  final List<BackupUploadItem> uploads;

  /// Ledger repairs to persist before/after uploads.
  final List<BackupAdoption> adoptions;

  /// Assets already backed up with an unchanged fingerprint.
  final int skippedKnown;

  /// Assets older than the rule creation cutoff while backfill is off (A2).
  final int skippedBackfill;

  /// Assets matched to an existing cloud copy by name + size (A7).
  final int skippedCloudAdopted;

  /// Assets larger than the whole per-run byte budget, skipped deliberately.
  final int skippedOversized;

  /// Assets excluded by the photos/videos type filters.
  final int skippedType;

  /// Whether per-run caps truncated the plan (E1).
  final bool capped;

  /// Constructs BackupPlan.
  const BackupPlan({
    required this.uploads,
    required this.adoptions,
    this.skippedKnown = 0,
    this.skippedBackfill = 0,
    this.skippedCloudAdopted = 0,
    this.skippedOversized = 0,
    this.skippedType = 0,
    this.capped = false,
  });

  /// Total assets intentionally not uploaded (for the run summary).
  int get skippedTotal =>
      skippedKnown + skippedBackfill + skippedCloudAdopted + skippedType;

  /// Total assets counted by the scheduler summary (skipped + oversized).
  int get accountedTotal => skippedTotal + skippedOversized;
}
/// An existing file in the destination folder, used for reconciliation (A7).
class CloudFileRef {
  /// TelStorage file id.
  final String fileId;

  /// File size in bytes.
  final int sizeBytes;

  /// Constructs CloudFileRef.
  const CloudFileRef({required this.fileId, required this.sizeBytes});
}

/// Returns [name], suffixed with ` (2)`, ` (3)`… when already taken (A8).
String uniqueDestinationName(String name, Set<String> takenNames) {
  if (!takenNames.contains(name)) return name;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var index = 2;
  while (takenNames.contains('$base ($index)$ext')) {
    index++;
  }
  return '$base ($index)$ext';
}
/// Plans one run: which assets to upload, which ledger rows to repair, and what
/// was skipped. Pure — no I/O, no hidden clock reads.
BackupPlan planRun({
  required BackupRule rule,
  required List<BackupAsset> assets,
  required Map<String, BackupLedgerEntry> ledgerByAssetId,
  required Map<String, BackupLedgerEntry> ledgerByPath,
  required Map<String, CloudFileRef> cloudFilesByName,
  int maxItems = 200,
  int maxBytes = 2147483648,
}) {
  final uploads = <BackupUploadItem>[];
  final adoptions = <BackupAdoption>[];
  final takenNames = cloudFilesByName.keys.toSet();
  final cutoffMs = rule.createdAt?.millisecondsSinceEpoch;
  var skippedKnown = 0;
  var skippedBackfill = 0;
var skippedCloudAdopted = 0;
  var skippedOversized = 0;
  var skippedType = 0;
  var plannedBytes = 0;
  var capped = false;

  // Photos before videos, oldest first, so capped runs advance over time (E2).
  final ordered = List<BackupAsset>.from(assets)
    ..sort((a, b) {
      if (a.isVideo != b.isVideo) return a.isVideo ? 1 : -1;
      return a.modifiedMs.compareTo(b.modifiedMs);
    });

  for (final asset in ordered) {
    if (asset.isVideo ? !rule.includeVideos : !rule.includePhotos) {
      skippedType++;
      continue;
    }

    final byId = ledgerByAssetId[asset.assetId];
    final byPath = ledgerByPath[asset.containerPath];
    final known = byId ?? byPath;

    if (known != null && known.fingerprint == asset.fingerprint) {
      if (byId == null) {
        adoptions.add(BackupAdoption(
          key: asset.assetId,
          fingerprint: asset.fingerprint,
          replacedKey: known.assetId,
          lastKnownPath: asset.containerPath,
          destFileId: known.destFileId,
        ));
      }
      skippedKnown++;
      continue;
    }

    // Conservative backfill gate (A2): while backfill is off, unknown
    // assets are skipped unless created after the rule. A missing cutoff
    // (createdAt == null) skips everything rather than risking an
    // accidental upload of the entire library.
    if (known == null && !rule.backfillDone) {
      if (cutoffMs == null || asset.modifiedMs < cutoffMs) {
        skippedBackfill++;
        continue;
      }
    }

    if (known == null) {
      final cloud = cloudFilesByName[asset.title];
      // Size tolerance mirrors the UploadService dedupe threshold (under
      // 0.01 MB) so an MB-to-bytes round trip never misses a match (A7).
      if (cloud != null &&
          (cloud.sizeBytes - asset.sizeBytes).abs() <= _reconcileToleranceBytes) {
        adoptions.add(BackupAdoption(
          key: asset.assetId,
          fingerprint: asset.fingerprint,
          lastKnownPath: asset.containerPath,
          destFileId: cloud.fileId,
        ));
        skippedCloudAdopted++;
        continue;
      }
    }

    if (asset.sizeBytes > maxBytes) {
      // A file larger than the whole run budget must never block the queue:
      // skip it explicitly and keep planning smaller items behind it (E1).
      skippedOversized++;
      continue;
    }
    if (uploads.length >= maxItems ||
        plannedBytes + asset.sizeBytes > maxBytes) {
      capped = true;
      break;
    }

    final destinationName = uniqueDestinationName(asset.title, takenNames);
    takenNames.add(destinationName);
    plannedBytes += asset.sizeBytes;

    uploads.add(BackupUploadItem(
      asset: asset,
      destinationName: destinationName,
      replacesFileId: known?.destFileId,
    ));
  }

  return BackupPlan(
    uploads: uploads,
    adoptions: adoptions,
    skippedKnown: skippedKnown,
    skippedBackfill: skippedBackfill,
    skippedCloudAdopted: skippedCloudAdopted,
    skippedOversized: skippedOversized,
    skippedType: skippedType,
    capped: capped,
  );
}
/// Chooses files to delete so at most [keepLast] ledger-backed files remain.
///
/// Only files attributed to backup via [ledgerFileIds] are ever deleted (D7);
/// user uploads inside the folder are left untouched. Oldest first.
List<FileRecord> selectRetentionDeletions({
  required List<FileRecord> folderFiles,
  required int keepLast,
  required Set<String> ledgerFileIds,
}) {
  if (keepLast <= 0) return const <FileRecord>[];
  final candidates = folderFiles
      .where((file) => ledgerFileIds.contains(file.fileId))
      .toList()
    ..sort((a, b) => a.uploadedAt.compareTo(b.uploadedAt));
  final excess = candidates.length - keepLast;
  if (excess <= 0) return const <FileRecord>[];
  return candidates.sublist(0, excess);
}

/// Injectable charging-state hook for [evaluateEligibility] (F1).
///
/// Defaults to unknown-is-charging; the worker must either back this with
/// `battery_plus` or mark the UI toggle coming-soon (implement-or-defer).
typedef ChargingStateProvider = Future<bool> Function();