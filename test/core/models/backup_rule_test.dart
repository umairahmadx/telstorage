/*
 * File: backup_rule_test.dart
 * Description: Unit tests for BackupRule safe defaults and BackupLedgerEntry key shape.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';

void main() {
  group('BackupRule', () {
    test('has safe v1 defaults', () {
      final rule = BackupRule(id: 'camera', albumName: 'Camera');

      expect(rule.enabled, isFalse);
      expect(rule.includePhotos, isTrue);
      expect(rule.includeVideos, isTrue);
      expect(rule.wifiOnly, isTrue);
      expect(rule.chargingOnly, isFalse);
      expect(rule.windowStartMinutes, 120);
      expect(rule.windowEndMinutes, 300);
      expect(rule.backfillDone, isFalse);
      expect(rule.backupFolderId, isNull);
      expect(rule.albumFolderId, isNull);
      expect(rule.retentionKeepLast, 0);
      expect(rule.lastRunAt, isNull);
    });

    test('window check handles normal and midnight-spanning windows', () {
      final rule = BackupRule(id: 'camera', albumName: 'Camera');

      expect(rule.isInWindow(DateTime(2026, 1, 1, 3, 0)), isTrue);
      expect(rule.isInWindow(DateTime(2026, 1, 1, 12, 0)), isFalse);

      final overnight = BackupRule(
        id: 'camera',
        albumName: 'Camera',
        windowStartMinutes: 1380,
        windowEndMinutes: 120,
      );
      expect(overnight.isInWindow(DateTime(2026, 1, 1, 23, 30)), isTrue);
      expect(overnight.isInWindow(DateTime(2026, 1, 1, 1, 0)), isTrue);
      expect(overnight.isInWindow(DateTime(2026, 1, 1, 12, 0)), isFalse);
    });
  });

  group('BackupLedgerEntry', () {
    test('builds fingerprint from asset identity without reading files', () {
      final fingerprint = BackupLedgerEntry.fingerprintFor(
        modifiedMs: 1700000000000,
        sizeBytes: 2048,
      );

      expect(fingerprint, isNotEmpty);
      // Edits change the fingerprint (A3)...
      expect(
        BackupLedgerEntry.fingerprintFor(
          modifiedMs: 1700000000001,
          sizeBytes: 2048,
        ),
        isNot(fingerprint),
      );
      // ...but a MediaStore id change does not (B1).
      expect(
        BackupLedgerEntry.fingerprintFor(
          modifiedMs: 1700000000000,
          sizeBytes: 2048,
        ),
        fingerprint,
      );
    });
  });
}
