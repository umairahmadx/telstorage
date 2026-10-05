/*
 * File: backup_ledger_entry.dart
 * Description: Hive model recording one backed-up device asset fingerprint for next-day idempotency.
 */

import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:hive/hive.dart';

part 'backup_ledger_entry.g.dart';

/// Hive local model recording that a device asset was backed up.
///
/// Keyed by the MediaStore asset id; the fingerprint detects edits, and
/// [lastKnownPath] recovers identity when vendor rescans change asset ids.
@HiveType(typeId: 5)
class BackupLedgerEntry extends HiveObject {
  /// Stable MediaStore asset identifier at backup time.
  @HiveField(0)
  String assetId;

  /// Content fingerprint `sha256(assetId + mtime + size)` — no file read.
  @HiveField(1)
  String fingerprint;

  /// Last known device path, used when the asset id changes (see B1).
  @HiveField(2)
  String? lastKnownPath;

  /// TelStorage file id of the uploaded copy, if still present.
  @HiveField(3)
  String? destFileId;

  /// TelStorage folder id the copy was uploaded into.
  @HiveField(4)
  String? destFolderId;

  /// When the copy was uploaded.
  @HiveField(5)
  DateTime? uploadedAt;

  /// Constructs BackupLedgerEntry.
  BackupLedgerEntry({
    required this.assetId,
    required this.fingerprint,
    this.lastKnownPath,
    this.destFileId,
    this.destFolderId,
    this.uploadedAt,
  });

  /// Builds a content fingerprint without reading the file bytes.
  ///
  /// Deliberately excludes the asset id: vendor rescans can change MediaStore
  /// ids while the bytes stay identical, and excluding the id lets path-based
  /// reconciliation recognise the same asset and skip a needless re-upload
  /// (edge case B1). Modified time plus size still detects edits (A3).
  static String fingerprintFor({
    required int modifiedMs,
    required int sizeBytes,
  }) {
    final bytes = utf8.encode('$modifiedMs|$sizeBytes');
    return sha256.convert(bytes).toString();
  }
}
