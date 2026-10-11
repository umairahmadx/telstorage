/*
 * File: auto_backup_service.dart
 * Description: Foreground bridge between the pure auto-backup engine and
 * device/cloud integrations (MediaStore scan, Backup folders, ledger).
 * Foreground only — never call from the Workmanager isolate.
 */

import 'package:hive/hive.dart';
import 'package:photo_manager/photo_manager.dart';

import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/services/auto_backup_types.dart';
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/folder_traversal_service.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/utils/app_logger.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/shared/widgets/device_file_picker/device_media_scanner.dart';

/// Foreground backup service wiring scan, folders, eligibility, retention.
///
/// Thin I/O shell around the pure engine: [collectDueAssets] scans the
/// MediaStore and diffs against the ledger, [ensureBackupPath] resolves the
/// destination folders, [advanceWatermark] persists completions, and
/// [enforceRetention] trims ledger-backed files. All async work returns
/// [Result]. Folder creation and deletions need the Telegram stack, so this
/// service must never run inside the Workmanager isolate (Task 4 calls only
/// the Hive-only due-check there).
class AutoBackupService {
  /// Maximum ledger rows before LRU eviction (E5).
  static const int maxLedgerEntries = 5000;

  /// Per-run caps bounding Telegram flood risk (E1).
  static const int defaultMaxItems = 200;

  /// Per-run byte budget (2 GB).
  static const int defaultMaxBytes = 2147483648;

  /// MediaStore page size bounding RAM (mirrors the media picker).
  static const int scanPageSize = 60;

  /// Safety ceiling stopping a runaway scan (500 pages x 60 assets).
  static const int maxScanPages = 500;

  final Box<BackupLedgerEntry>? _ledgerBox;
  final HiveService _hive;
  final FileManagerService? _files;
  final BackupRequestPermission _requestPermission;
  final BackupLoadAlbums _loadAlbums;
  final BackupLoadPage _loadPage;
  final UnmeteredProvider _isUnmetered;
  final ChargingStateProvider _isCharging;
  final FreeSpaceProvider _freeSpaceBytes;

  /// Constructs AutoBackupService with injectable hooks for tests.
  AutoBackupService({
    Box<BackupLedgerEntry>? ledgerBox,
    HiveService? hive,
    FileManagerService? fileManager,
    BackupRequestPermission? requestPermission,
    BackupLoadAlbums? loadAlbums,
    BackupLoadPage? loadPage,
    UnmeteredProvider? isUnmetered,
    ChargingStateProvider? isCharging,
    FreeSpaceProvider? freeSpaceBytes,
  })  : _ledgerBox = ledgerBox,
        _hive = hive ?? HiveService.instance,
        _files = fileManager,
        _requestPermission =
            requestPermission ?? DeviceMediaScanner.requestPermission,
        _loadAlbums = loadAlbums ?? DeviceMediaScanner.loadAlbums,
        _loadPage = loadPage ??
            ((album, page, pageSize) => DeviceMediaScanner.loadAlbumMedia(
                  album,
                  page: page,
                  pageSize: pageSize,
                )),
        _isUnmetered = isUnmetered ?? Connectivity.isUnmetered,
        // F1 advisory: unknown charging state treats device as charging.
        _isCharging = isCharging ?? (() async => true),
        // E3: unknown free space proceeds; Android zero-copy needs no temp.
        _freeSpaceBytes = freeSpaceBytes ?? (() async => null);

  /// Resolves the ledger box keyed by asset id (opened in main.dart).
  Box<BackupLedgerEntry> get _ledger =>
      _ledgerBox ?? Hive.box<BackupLedgerEntry>(AppConstants.backupLedgerBox);

  /// Evaluates whether [rule] may run now (no permission prompt here).
  ///
  /// Order: disabled, window (C7 midnight wrap via isInWindow), unmetered
  /// (C4), charging (F1 advisory). Permission is gated in [collectDueAssets]
  /// (F2) so background due-checks never prompt the user.
  Future<Result<BackupEligibility>> isEligibleNow(
    BackupRule rule, {
    DateTime? now,
  }) async {
    try {
      if (!rule.enabled) {
        return const Success(BackupEligibility(BackupBlockReason.disabled));
      }
      if (!rule.isInWindow(now ?? DateTime.now())) {
        return const Success(
            BackupEligibility(BackupBlockReason.outsideWindow));
      }
      if (rule.wifiOnly && !await _isUnmetered()) {
        return const Success(BackupEligibility(BackupBlockReason.metered));
      }
      if (rule.chargingOnly && !await _isCharging()) {
        return const Success(BackupEligibility(BackupBlockReason.notCharging));
      }
      return const Success(BackupEligibility(BackupBlockReason.ready));
    } catch (e) {
      return Failure(UnknownFailure('Eligibility check failed: $e', e));
    }
  }

  /// Scans the rule album, diffs against the ledger, plans one run.
  ///
  /// Gates on permission (F2: deny yields a Failure, never a crash).
  /// Enumerates in 60-asset pages, converts to [BackupAsset] DTOs with no
  /// file reads, persists path/cloud adoptions immediately, and applies
  /// per-run caps (E1/E2).
  Future<Result<BackupCollectResult>> collectDueAssets(
    BackupRule rule, {
    int maxItems = defaultMaxItems,
    int maxBytes = defaultMaxBytes,
  }) async {
    try {
      if (!rule.enabled) {
        return const Success(BackupCollectResult(
          plan: BackupPlan(uploads: [], adoptions: []),
        ));
      }
      if (!await _requestPermission()) {
        return const Failure(UnknownFailure('Permission needed'));
      }
      final albums = await _loadAlbums();
      final album = _findAlbum(albums, rule.albumName);
      if (album == null) {
        return Failure(NotFoundFailure('Album "${rule.albumName}" missing'));
      }
      final scanned = await _scanAlbum(album);
      final cloudByName = _cloudFilesByName(rule.albumFolderId);
      final byId = <String, BackupLedgerEntry>{};
      final byPath = <String, BackupLedgerEntry>{};
      for (final entry in _ledger.values) {
        byId[entry.assetId] = entry;
        final path = entry.lastKnownPath;
        if (path != null) byPath[path] = entry;
      }
      final plan = planRun(
        rule: rule,
        assets: scanned.assets,
        ledgerByAssetId: byId,
        ledgerByPath: byPath,
        cloudFilesByName: cloudByName,
        maxItems: maxItems,
        maxBytes: maxBytes,
      );
      await _persistAdoptions(plan.adoptions, rule);
      return Success(BackupCollectResult(
        plan: plan,
        skippedUnresolvable: scanned.skippedUnresolvable,
      ));
    } catch (e) {
      return Failure(UnknownFailure('Backup scan failed: $e', e));
    }
  }

  /// Resolves `root/Backup/<Album>` idempotently, adopting collisions (D5).
  ///
  /// Matches `(name == Backup, parentId == null)` first and adopts it;
  /// creates via [FileManagerService.createFolder] only when missing, then
  /// matches-or-creates the sanitized album child. Caches both ids on
  /// [rule] when supplied. Foreground only.
  Future<Result<BackupPath>> ensureBackupPath(
    String albumName, {
    BackupRule? rule,
  }) async {
    try {
      final files = _files;
      if (files == null) {
        return const Failure(
            UnknownFailure('FileManager missing for backup folders'));
      }
      final sanitized = FolderTraversalService.sanitizeSegment(albumName);
      var folders = _hive.allFolders;
      var matches =
          folders.where((f) => f.name == 'Backup' && f.parentId == null);
      var backupId = matches.isNotEmpty ? matches.first.id : null;
      if (backupId == null) {
        await files.createFolder('Backup');
        folders = _hive.allFolders;
        matches =
            folders.where((f) => f.name == 'Backup' && f.parentId == null);
        if (matches.isEmpty) {
          return const Failure(
              UnknownFailure('Could not resolve Backup folder'));
        }
        backupId = matches.first.id;
      }
      final resolvedBackupId = backupId;
      var albumMatches = folders.where(
        (f) => f.parentId == resolvedBackupId && f.name == sanitized,
      );
      var albumId = albumMatches.isNotEmpty ? albumMatches.first.id : null;
      if (albumId == null) {
        await files.createFolder(sanitized, parentId: resolvedBackupId);
        folders = _hive.allFolders;
        albumMatches = folders.where(
          (f) => f.parentId == resolvedBackupId && f.name == sanitized,
        );
        if (albumMatches.isEmpty) {
          return const Failure(
              UnknownFailure('Could not resolve backup album folder'));
        }
        albumId = albumMatches.first.id;
      }
      if (rule != null) {
        rule.backupFolderId = resolvedBackupId;
        rule.albumFolderId = albumId;
        await _saveRule(rule);
      }
      return Success(BackupPath(
        backupFolderId: resolvedBackupId,
        albumFolderId: albumId,
      ));
    } catch (e) {
      return Failure(UnknownFailure('Backup path setup failed: $e', e));
    }
  }

  /// Persists ledger rows for completed uploads only (never batch end).
  ///
  /// Skips assets missing from [destFileIdsByAssetId] so uncompleted items
  /// keep no ledger entry (E4). Deletes replaced cloud copies for edited
  /// assets (A3) best-effort, then evicts the ledger LRU (E5) and stamps
  /// the rule run outcome.
  Future<Result<void>> advanceWatermark({
    required BackupRule rule,
    required List<BackupUploadItem> uploads,
    required Map<String, String> destFileIdsByAssetId,
    String? destFolderId,
    bool deleteReplaced = true,
  }) async {
    try {
      final now = DateTime.now();
      var completed = 0;
      for (final upload in uploads) {
        final destFileId = destFileIdsByAssetId[upload.asset.assetId];
        if (destFileId == null) continue;
        final replaced = upload.replacesFileId;
        if (deleteReplaced && replaced != null && _files != null) {
          try {
            await _files.deleteFile(replaced);
          } catch (e) {
            AppLogger.w('Backup: replaced delete failed $replaced: $e',
                tag: 'AutoBackup');
          }
        }
        await _ledger.put(
          upload.asset.assetId,
          BackupLedgerEntry(
            assetId: upload.asset.assetId,
            fingerprint: upload.asset.fingerprint,
            lastKnownPath: upload.asset.containerPath,
            destFileId: destFileId,
            destFolderId: destFolderId ?? rule.albumFolderId,
            uploadedAt: now,
          ),
        );
        completed++;
      }
      await _evictLedgerIfNeeded();
      rule.lastRunAt = now;
      rule.lastResult = 'completed';
      rule.lastUploadedCount = completed;
      await _saveRule(rule);
      return const Success(null);
    } catch (e) {
      return Failure(UnknownFailure('Backup watermark failed: $e', e));
    }
  }

  /// Deletes oldest ledger-backed files beyond keep-last-N (D7).
  ///
  /// Only files attributed via the ledger inside the album folder are ever
  /// deleted; manual uploads are untouched. Ledger rows for deleted copies
  /// are pruned so the next scan does not re-queue them (A6).
  Future<Result<int>> enforceRetention(BackupRule rule) async {
    try {
      if (rule.retentionKeepLast <= 0) return const Success(0);
      final albumFolderId = rule.albumFolderId;
      if (albumFolderId == null) {
        return const Failure(
            NotFoundFailure('Backup path missing for retention'));
      }
      final files = _files;
      if (files == null) {
        return const Failure(
            UnknownFailure('FileManager missing for retention'));
      }
      final folderFiles = _hive.filesInFolder(albumFolderId);
      final ledgerFileIds = <String>{};
      for (final entry in _ledger.values) {
        final id = entry.destFileId;
        if (id != null) ledgerFileIds.add(id);
      }
      final doomed = selectRetentionDeletions(
        folderFiles: folderFiles,
        keepLast: rule.retentionKeepLast,
        ledgerFileIds: ledgerFileIds,
      );
      var deleted = 0;
      final deletedIds = <String>{};
      for (final file in doomed) {
        try {
          await files.deleteFile(file.fileId);
          deleted++;
          deletedIds.add(file.fileId);
        } catch (e) {
          AppLogger.w('Backup: retention delete failed ${file.fileId}: $e',
              tag: 'AutoBackup');
        }
      }
      if (deletedIds.isNotEmpty) {
        for (final entry in _ledger.values.toList()) {
          if (entry.destFileId != null &&
              deletedIds.contains(entry.destFileId)) {
            await _ledger.delete(entry.assetId);
          }
        }
      }
      return Success(deleted);
    } catch (e) {
      return Failure(UnknownFailure('Backup retention failed: $e', e));
    }
  }

  /// Pre-flight free-space guard (E3): skips below 2x the largest file.
  ///
  /// Null probe results mean unknown and proceed (Android zero-copy needs
  /// no temp space; iOS temp copies are bounded per-file).
  Future<Result<void>> ensureFreeSpaceFor(List<BackupAsset> assets) async {
    try {
      if (assets.isEmpty) return const Success(null);
      var largest = 0;
      for (final asset in assets) {
        if (asset.sizeBytes > largest) largest = asset.sizeBytes;
      }
      final free = await _freeSpaceBytes();
      if (free == null) return const Success(null);
      if (free < 2 * largest) {
        return const Failure(
            QuotaExceededFailure('Low device storage for backup'));
      }
      return const Success(null);
    } catch (e) {
      return Failure(UnknownFailure('Free-space check failed: $e', e));
    }
  }

  /// Persists a rule when it lives in the rules box, else a no-op.
  ///
  /// Unit tests build detached rules (not added to any box); calling
  /// [HiveObject.save] on those throws, so only attached rules persist.
  /// Field mutations still apply in memory for both cases.
  Future<void> _saveRule(BackupRule rule) async {
    if (!rule.isInBox) return;
    try {
      await rule.save();
    } catch (e) {
      AppLogger.w('Backup: rule save skipped: $e', tag: 'AutoBackup');
    }
  }

  /// Matches the rule album by exact name, then case-insensitively.
  MediaAlbum? _findAlbum(List<MediaAlbum> albums, String name) {
    for (final album in albums) {
      if (album.name == name) return album;
    }
    final lower = name.toLowerCase();
    for (final album in albums) {
      if (album.name.toLowerCase() == lower) return album;
    }
    return null;
  }

  /// Pages through one album converting to engine DTOs without file reads.
  Future<({List<BackupAsset> assets, int skippedUnresolvable})> _scanAlbum(
    MediaAlbum album,
  ) async {
    final assets = <BackupAsset>[];
    var skippedUnresolvable = 0;
    for (var page = 0; page < maxScanPages; page++) {
      final slice = await _loadPage(album, page, scanPageSize);
      if (slice.isEmpty) break;
      for (final entity in slice) {
        final dto = await _toBackupAsset(entity);
        if (dto == null) {
          skippedUnresolvable++;
          continue;
        }
        assets.add(dto);
      }
      if (slice.length < scanPageSize) break;
    }
    return (assets: assets, skippedUnresolvable: skippedUnresolvable);
  }

  /// Converts one AssetEntity to a DTO; null when metadata is unreadable.
  Future<BackupAsset?> _toBackupAsset(AssetEntity entity) async {
    try {
      final rawTitle = entity.title;
      final title =
          (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : entity.id;
      final modifiedSec = entity.modifiedDateSecond ?? entity.createDateSecond;
      final modifiedMs = (modifiedSec ??
              DateTime.now().millisecondsSinceEpoch ~/ 1000) *
          1000;
      int sizeBytes = 0;
      try {
        sizeBytes = await entity.fileSize;
      } catch (_) {
        return null;
      }
      return BackupAsset(
        assetId: entity.id,
        title: title,
        relativePath: entity.relativePath,
        modifiedMs: modifiedMs,
        sizeBytes: sizeBytes,
        isVideo: entity.type == AssetType.video,
      );
    } catch (_) {
      return null;
    }
  }

  /// Indexes existing destination files by name for cloud adoption (A7).
  Map<String, CloudFileRef> _cloudFilesByName(String? albumFolderId) {
    final map = <String, CloudFileRef>{};
    if (albumFolderId == null) return map;
    for (final file in _hive.filesInFolder(albumFolderId)) {
      if (map.containsKey(file.name)) continue;
      map[file.name] = CloudFileRef(
        fileId: file.fileId,
        sizeBytes: (file.sizeMb * 1048576).round(),
      );
    }
    return map;
  }

  /// Persists B1/A7 adoptions, migrating renamed MediaStore ids.
  Future<void> _persistAdoptions(
    List<BackupAdoption> adoptions,
    BackupRule rule,
  ) async {
    if (adoptions.isEmpty) return;
    final now = DateTime.now();
    for (final adoption in adoptions) {
      if (adoption.replacedKey != null &&
          adoption.replacedKey != adoption.key) {
        await _ledger.delete(adoption.replacedKey!);
      }
      await _ledger.put(
        adoption.key,
        BackupLedgerEntry(
          assetId: adoption.key,
          fingerprint: adoption.fingerprint,
          lastKnownPath: adoption.lastKnownPath,
          destFileId: adoption.destFileId,
          destFolderId: rule.albumFolderId,
          uploadedAt: now,
        ),
      );
    }
    await _evictLedgerIfNeeded();
  }

  /// Caps the ledger at [maxLedgerEntries] rows, oldest first (E5).
  Future<void> _evictLedgerIfNeeded() async {
    if (_ledger.length <= maxLedgerEntries) return;
    final sorted = _ledger.values.toList()
      ..sort((a, b) {
        final at = a.uploadedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.uploadedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return at.compareTo(bt);
      });
    final excess = _ledger.length - maxLedgerEntries;
    for (var i = 0; i < excess; i++) {
      await _ledger.delete(sorted[i].assetId);
    }
  }
}
