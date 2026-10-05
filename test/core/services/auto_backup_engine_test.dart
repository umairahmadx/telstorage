/*
 * File: auto_backup_engine_test.dart
 * Description: Unit tests for the auto-backup engine covering diff, eligibility, retention, reconciliation, and scale caps.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
BackupRule cameraRule({
  bool enabled = true,
  bool backfillDone = true,
  DateTime? createdAt,
  int retentionKeepLast = 0,
}) {
  return BackupRule(
    id: 'camera',
    albumName: 'Camera',
    enabled: enabled,
    backfillDone: backfillDone,
    createdAt: createdAt ?? DateTime(2025, 6, 1),
    retentionKeepLast: retentionKeepLast,
  );
}

BackupAsset photo({
  required String id,
  required String title,
  int modifiedMs = 1749000000000,
  int sizeBytes = 1024,
  bool isVideo = false,
  String? relativePath,
}) {
  return BackupAsset(
    assetId: id,
    title: title,
    relativePath: relativePath,
    modifiedMs: modifiedMs,
    sizeBytes: sizeBytes,
    isVideo: isVideo,
  );
}

BackupLedgerEntry ledgerRow({
  required String assetId,
  required BackupAsset asset,
  String? destFileId,
}) {
  return BackupLedgerEntry(
    assetId: assetId,
    fingerprint: asset.fingerprint,
    lastKnownPath: asset.containerPath,
    destFileId: destFileId ?? 'f-$assetId',
    destFolderId: 'album-folder',
    uploadedAt: DateTime(2025, 7, 1),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('planRun diff', () {
    test('unchanged ledger assets are skipped (A1)', () {
      final rule = cameraRule();
      final asset = photo(id: 'a1', title: 'IMG_001.jpg');
      final plan = planRun(
        rule: rule,
        assets: [asset],
        ledgerByAssetId: {'a1': ledgerRow(assetId: 'a1', asset: asset)},
        ledgerByPath: {},
        cloudFilesByName: {},
      );
      expect(plan.uploads, isEmpty);
      expect(plan.skippedKnown, 1);
    });
    test('edited asset is due again and replaces the old copy (A3)', () {
      final rule = cameraRule();
      final old = photo(id: 'a1', title: 'IMG_001.jpg', modifiedMs: 1749000000000);
      final edited = photo(id: 'a1', title: 'IMG_001.jpg', modifiedMs: 1749100000000);
      final plan = planRun(
        rule: rule,
        assets: [edited],
        ledgerByAssetId: {'a1': ledgerRow(assetId: 'a1', asset: old, destFileId: 'old-file')},
        ledgerByPath: {},
        cloudFilesByName: {},
      );
      expect(plan.uploads, hasLength(1));
      expect(plan.uploads.first.replacesFileId, 'old-file');
    });

    test('unknown asset is due when backfill is on', () {
      final rule = cameraRule(backfillDone: true);
      final plan = planRun(
        rule: rule,
        assets: [photo(id: 'a9', title: 'IMG_009.jpg', modifiedMs: 1740000000000)],
        ledgerByAssetId: {},
        ledgerByPath: {},
        cloudFilesByName: {},
      );
      expect(plan.uploads, hasLength(1));
    });

    test('pre-cutoff asset is skipped while backfill is off (A2)', () {
      final rule = cameraRule(backfillDone: false, createdAt: DateTime(2025, 6, 1));
      final plan = planRun(
        rule: rule,
        assets: [photo(id: 'a9', title: 'IMG_009.jpg', modifiedMs: DateTime(2025, 1, 1).millisecondsSinceEpoch)],
        ledgerByAssetId: {},
        ledgerByPath: {},
        cloudFilesByName: {},
      );
      expect(plan.uploads, isEmpty);
      expect(plan.skippedBackfill, 1);
    });

    test('path adoption avoids re-upload after MediaStore id change (B1)', () {
      final rule = cameraRule();
      final old = photo(id: 'old-id', title: 'IMG_001.jpg', relativePath: 'DCIM/Camera/');
      final rescanned = photo(id: 'new-id', title: 'IMG_001.jpg', relativePath: 'DCIM/Camera/');
      final entry = ledgerRow(assetId: 'old-id', asset: old, destFileId: 'cloud-1');
      final plan = planRun(
        rule: rule,
        assets: [rescanned],
        ledgerByAssetId: {},
        ledgerByPath: {'DCIM/Camera/IMG_001.jpg': entry},
        cloudFilesByName: {},
      );
      expect(plan.uploads, isEmpty);
      expect(plan.skippedKnown, 1);
      expect(plan.adoptions, hasLength(1));
      expect(plan.adoptions.first.key, 'new-id');
      expect(plan.adoptions.first.replacedKey, 'old-id');
      expect(plan.adoptions.first.destFileId, 'cloud-1');
    });

    test('existing cloud copy is adopted instead of re-uploaded (A7)', () {
      final rule = cameraRule(backfillDone: false);
      final asset = photo(id: 'a9', title: 'IMG_009.jpg', sizeBytes: 2048);
      final plan = planRun(
        rule: rule,
        assets: [asset],
        ledgerByAssetId: {},
        ledgerByPath: {},
        cloudFilesByName: {'IMG_009.jpg': const CloudFileRef(fileId: 'cloud-9', sizeBytes: 2048)},
      );
      expect(plan.uploads, isEmpty);
      expect(plan.skippedCloudAdopted, 1);
      expect(plan.adoptions.first.destFileId, 'cloud-9');
    });

    test('retaken filename is suffixed, never overwritten (A8)', () {
      final rule = cameraRule();
      final asset = photo(id: 'a9', title: 'IMG_009.jpg');
      final plan = planRun(
        rule: rule,
        assets: [asset],
        ledgerByAssetId: {},
        ledgerByPath: {},
        cloudFilesByName: {'IMG_009.jpg': const CloudFileRef(fileId: 'other', sizeBytes: 99999)},
      );
      expect(plan.uploads, hasLength(1));
      expect(plan.uploads.first.destinationName, 'IMG_009 (2).jpg');
    });
  });
  group('planRun eligibility', () {
    test('disabled rule is not eligible', () {
      final rule = cameraRule(enabled: false);
      final verdict = evaluateEligibility(
        rule: rule,
        now: DateTime(2026, 1, 1, 3),
        unmetered: true,
        charging: true,
        permissionGranted: true,
      );
      expect(verdict.isEligible, isFalse);
      expect(verdict.reason, BackupBlockReason.disabled);
    });

    test('metered network blocks wifi-only rules', () {
      final verdict = evaluateEligibility(
        rule: cameraRule(),
        now: DateTime(2026, 1, 1, 3),
        unmetered: false,
        charging: true,
        permissionGranted: true,
      );
      expect(verdict.reason, BackupBlockReason.metered);
    });

    test('window uses local minutes with midnight wrap', () {
      final rule = cameraRule();
      BackupEligibility at(int h, int m) => evaluateEligibility(
            rule: rule,
            now: DateTime(2026, 1, 1, h, m),
            unmetered: true,
            charging: true,
            permissionGranted: true,
          );
      expect(at(2, 30).isEligible, isTrue);
      expect(at(5, 0).reason, BackupBlockReason.outsideWindow);
      expect(at(23, 0).reason, BackupBlockReason.outsideWindow);
    });
  });

  group('retention selection', () {
    FileRecord cloudFile(String id, DateTime at) => FileRecord(
          fileId: id,
          name: 'IMG_$id.jpg',
          folderId: 'album-folder',
          metadataMessageId: 1,
          sizeMb: 1,
          mimeType: 'image/jpeg',
          uploadedAt: at,
          chunkCount: 1,
          sha256Hash: 'h',
        );

    test('keeps newest N ledger files and deletes oldest (D7)', () {
      final files = List.generate(
        5,
        (i) => cloudFile('f$i', DateTime(2025, 7, i + 1)),
      );
      final doomed = selectRetentionDeletions(
        folderFiles: files,
        keepLast: 3,
        ledgerFileIds: {'f0', 'f1', 'f2', 'f3', 'f4'},
      );
      expect(doomed.map((f) => f.fileId), ['f0', 'f1']);
    });

    test('manual uploads in the folder are never deleted', () {
      final files = [
        cloudFile('f0', DateTime(2025, 7, 1)),
        cloudFile('manual', DateTime(2025, 1, 1)),
      ];
      final doomed = selectRetentionDeletions(
        folderFiles: files,
        keepLast: 1,
        ledgerFileIds: {'f0'},
      );
      expect(doomed, isEmpty);
    });
  });

  group('scale caps', () {
    test('per-run item cap truncates oldest-last (E1)', () {
      final rule = cameraRule();
      final assets = List.generate(
        5,
        (i) => photo(id: 'c$i', title: 'IMG_00$i.jpg', modifiedMs: 1749000000000 + i),
      );
      final plan = planRun(
        rule: rule,
        assets: assets,
        ledgerByAssetId: {},
        ledgerByPath: {},
        cloudFilesByName: {},
        maxItems: 2,
      );
      expect(plan.uploads.map((u) => u.asset.assetId), ['c0', 'c1']);
      expect(plan.capped, isTrue);
    });

    test('missing cutoff skips unknown assets rather than mass-uploading', () {
      final rule = cameraRule(backfillDone: false);
      rule.createdAt = null;
      final plan = planRun(
        rule: rule,
        assets: [photo(id: 'x1', title: 'IMG_X.jpg')],
        ledgerByAssetId: {},
        ledgerByPath: {},
        cloudFilesByName: {},
      );
      expect(plan.uploads, isEmpty);
      expect(plan.skippedBackfill, 1);
    });

    test('oversized file is skipped without blocking smaller files (E1)', () {
      final rule = cameraRule();
      const gb = 1024 * 1024 * 1024;
      final assets = [
        photo(id: 'big', title: 'MOV_BIG.mp4', isVideo: true, sizeBytes: 3 * gb),
        photo(id: 'small', title: 'IMG_S.jpg', sizeBytes: 1024),
      ];
      final plan = planRun(
        rule: rule,
        assets: assets,
        ledgerByAssetId: {},
        ledgerByPath: {},
        cloudFilesByName: {},
      );
      expect(plan.uploads.map((u) => u.asset.assetId), ['small']);
      expect(plan.skippedOversized, 1);
      expect(plan.accountedTotal, 1);
    });

    test('excluded media types are counted, not uploaded', () {
      final rule = cameraRule();
      rule.includeVideos = false;
      final plan = planRun(
        rule: rule,
        assets: [
          photo(id: 'v1', title: 'MOV_1.mp4', isVideo: true),
          photo(id: 'p1', title: 'IMG_1.jpg'),
        ],
        ledgerByAssetId: {},
        ledgerByPath: {},
        cloudFilesByName: {},
      );
      expect(plan.uploads.map((u) => u.asset.assetId), ['p1']);
      expect(plan.skippedType, 1);
    });

    test('size tolerance still matches after an MB round trip (A7)', () {
      final rule = cameraRule(backfillDone: false);
      final asset = photo(id: 't1', title: 'IMG_T.jpg', sizeBytes: 3211264);
      final cloudBytes = ((3211264 / 1048576) * 1048576).round();
      final plan = planRun(
        rule: rule,
        assets: [asset],
        ledgerByAssetId: {},
        ledgerByPath: {},
        cloudFilesByName: {'IMG_T.jpg': CloudFileRef(fileId: 'cloud-t', sizeBytes: cloudBytes)},
      );
      expect(plan.uploads, isEmpty);
      expect(plan.skippedCloudAdopted, 1);
    });

    test('extensionless names get numeric suffixes without a dot', () {
      final taken = <String>{'README'};
      expect(uniqueDestinationName('README', taken), 'README (2)');
      expect(uniqueDestinationName('photo.', taken), 'photo.');
    });
  });
}
