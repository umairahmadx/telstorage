/*
 * File: hive_service.dart
 * Description: Local cache management and defensive box initialization with quarantine preservation for corrupted storage states.
 */

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';
import '../events/domain_event_bus.dart';
import '../models/file_record.dart';
import '../models/folder_record.dart';
import '../utils/app_logger.dart';

/// Local cache management using Hive
class HiveService {
  static final HiveService instance = HiveService._();
  HiveService._();

  /// Defensively opens a Hive box, catching corrupted disk writes,
  /// preserving quarantine backups for critical state (e.g. pending_actions),
  /// and recreating a clean box without crashing the app on startup.
  static Future<Box<T>> openBoxDefensively<T>(
    String boxName, {
    bool preserveQuarantine = false,
    String? directory,
  }) async {
    Uint8List? preOpenBytes;

    if (directory != null) {
      final boxFilePath = '$directory/$boxName.hive';
      final file = File(boxFilePath);
      try {
        if (await file.exists() && await file.length() > 0) {
          preOpenBytes = await file.readAsBytes();
        }
      } catch (_) {}
    }

    try {
      if (Hive.isBoxOpen(boxName)) {
        return Hive.box<T>(boxName);
      }

      final box = await Hive.openBox<T>(boxName);

      // Detect if Hive silently truncated corrupted frames to empty
      if (preOpenBytes != null && preOpenBytes.isNotEmpty && box.isEmpty) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        String? quarantinedPath;

        if (preserveQuarantine) {
          quarantinedPath = '$directory/$boxName.hive.corrupted_$timestamp';
          try {
            await File(quarantinedPath).writeAsBytes(preOpenBytes, flush: true);
          } catch (e) {
            AppLogger.e(
              'Failed to save quarantine file: $e',
              tag: 'HiveService',
            );
          }

          AppLogger.w(
            'Critical box "$boxName" contained data on disk but was recovered empty. Quarantined original to $quarantinedPath',
            tag: 'HiveService',
          );

          DomainEventBus.instance.fire(
            CriticalBoxCorruptedEvent(
              boxName: boxName,
              quarantinedPath: quarantinedPath,
            ),
          );
        } else {
          AppLogger.w(
            'Cache box "$boxName" was corrupted and reset to empty state.',
            tag: 'HiveService',
          );
          DomainEventBus.instance.fire(
            PartitionCacheCorruptedEvent(boxName: boxName),
          );
        }
      }

      return box;
    } catch (e, stack) {
      AppLogger.e(
        'Hive box "$boxName" failed to open (fatal disk corruption): $e',
        tag: 'HiveService',
        error: e,
        stackTrace: stack,
      );

      String? quarantinedPath;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      if (preserveQuarantine &&
          preOpenBytes != null &&
          preOpenBytes.isNotEmpty) {
        quarantinedPath = '$directory/$boxName.hive.corrupted_$timestamp';
        try {
          await File(quarantinedPath).writeAsBytes(preOpenBytes, flush: true);
        } catch (_) {}

        DomainEventBus.instance.fire(
          CriticalBoxCorruptedEvent(
            boxName: boxName,
            quarantinedPath: quarantinedPath,
          ),
        );
      } else {
        DomainEventBus.instance.fire(
          PartitionCacheCorruptedEvent(boxName: boxName),
        );
      }

      final recoveryDir =
          directory != null ? '$directory/recovered_$timestamp' : null;
      if (recoveryDir != null) {
        try {
          await Directory(recoveryDir).create(recursive: true);
        } catch (_) {}
      }

      return await Hive.openBox<T>(
        boxName,
        path: recoveryDir,
      );
    }
  }

  Box<FileRecord> get _files => Hive.box<FileRecord>(AppConstants.filesBox);
  Box<FolderRecord> get _folders =>
      Hive.box<FolderRecord>(AppConstants.foldersBox);

  ValueListenable<Box<FileRecord>> get filesListenable => _files.listenable();
  ValueListenable<Box<FolderRecord>> get foldersListenable =>
      _folders.listenable();

  // ── File Operations ──────────────────────────────────────

  List<FileRecord> filesInFolder(String? folderId) {
    return _files.values.where((f) => f.folderId == folderId).toList();
  }

  List<FileRecord> recentFiles(int n) {
    final all = _files.values.toList()
      ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    return all.take(n).toList();
  }

  FileRecord? getFile(String fileId) {
    return _files.get(fileId);
  }

  Future<void> saveFile(FileRecord record) async {
    await _files.put(record.fileId, record);
  }

  /// Sentinel value meaning "move to root" when passed as [folderId].
  static const String kRootFolderId = '__root__';

  Future<void> updateFile(
    String fileId, {
    String? name,

    /// Pass [HiveService.kRootFolderId] to move the file to the root folder.
    String? folderId,
    bool clearFolderId = false,
    int? metadataMsgId,
    String? metadataFileId,
  }) async {
    final record = _files.get(fileId);
    if (record == null) return;

    if (name != null) record.name = name;
    if (clearFolderId) {
      record.folderId = null;
    } else if (folderId != null && folderId != kRootFolderId) {
      record.folderId = folderId;
    } else if (folderId == kRootFolderId) {
      record.folderId = null;
    }
    if (metadataMsgId != null) record.metadataMessageId = metadataMsgId;
    if (metadataFileId != null) record.metadataFileId = metadataFileId;

    await record.save();
  }

  Future<void> deleteFile(String fileId) async {
    await _files.delete(fileId);
  }

  // ── Folder Operations ────────────────────────────────────

  List<FolderRecord> subfolders(String? parentId) {
    return _folders.values.where((f) => f.parentId == parentId).toList();
  }

  FolderRecord? getFolder(String folderId) {
    return _folders.get(folderId);
  }

  Future<void> saveFolder(FolderRecord record) async {
    await _folders.put(record.id, record);
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final record = _folders.get(folderId);
    if (record == null) return;

    record.name = newName;
    await record.save();
  }

  Future<void> moveFolder(String folderId, String? parentId) async {
    final record = _folders.get(folderId);
    if (record == null) return;

    record.parentId = parentId;
    await record.save();
  }

  Future<void> deleteFolder(String folderId) async {
    await _folders.delete(folderId);
  }

  // ── Stats ────────────────────────────────────────────────

  int get totalFiles => _files.length;
  int get totalFolders => _folders.length;

  List<FileRecord> get allFiles => _files.values.toList();
  List<FolderRecord> get allFolders => _folders.values.toList();

  double get totalSizeMb {
    return _files.values.fold(0.0, (sum, file) => sum + file.sizeMb);
  }

  Map<String, int> get categoryCount {
    final counts = <String, int>{
      'images': 0,
      'videos': 0,
      'docs': 0,
      'others': 0,
    };

    for (final file in _files.values) {
      if (file.isImage) {
        counts['images'] = counts['images']! + 1;
      } else if (file.isVideo) {
        counts['videos'] = counts['videos']! + 1;
      } else if (file.isPdf) {
        counts['docs'] = counts['docs']! + 1;
      } else {
        counts['others'] = counts['others']! + 1;
      }
    }

    return counts;
  }

  // ── Clear All ────────────────────────────────────────────

  Future<void> clearAll() async {
    await _files.clear();
    await _folders.clear();
  }
}
