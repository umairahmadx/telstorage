/*
 * File: auto_backup_ledger.dart
 * Description: Ledger persistence helpers extracted from AutoBackupService
 * to keep the service within the 500-line file limit. Handles B1/A7
 * adoption writes and E5 LRU eviction against the Hive ledger box.
 */

import 'package:hive/hive.dart';

import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';

/// Caps the ledger at [maxEntries] rows, oldest first (E5).
///
/// Prunes the lowest-[BackupLedgerEntry.uploadedAt] rows when the box
/// exceeds the cap so re-scans stay bounded.
Future<void> evictLedgerIfNeeded(
  Box<BackupLedgerEntry> ledger, {
  int maxEntries = 5000,
}) async {
  if (ledger.length <= maxEntries) return;
  final sorted = ledger.values.toList()
    ..sort((a, b) {
      final at = a.uploadedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.uploadedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });
  final excess = ledger.length - maxEntries;
  for (var i = 0; i < excess; i++) {
    await ledger.delete(sorted[i].assetId);
  }
}

/// Persists B1/A7 adoptions, migrating renamed MediaStore ids.
///
/// Writes one ledger row per adoption, deletes replaced keys when the
/// id changed, then applies LRU eviction. [rule]'s album folder id is
/// stamped on each row.
Future<void> persistAdoptions(
  Box<BackupLedgerEntry> ledger,
  List<BackupAdoption> adoptions,
  BackupRule rule,
) async {
  if (adoptions.isEmpty) return;
  final now = DateTime.now();
  for (final adoption in adoptions) {
    if (adoption.replacedKey != null && adoption.replacedKey != adoption.key) {
      await ledger.delete(adoption.replacedKey!);
    }
    await ledger.put(
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
  await evictLedgerIfNeeded(ledger);
}