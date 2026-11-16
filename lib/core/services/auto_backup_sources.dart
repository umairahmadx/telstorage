/*
 * File: auto_backup_sources.dart
 * Description: Source-scan and destination-tree helpers extracted from
 * AutoBackupService to keep the service within the 500-line file limit.
 * Covers directory-tree scanning, cloud adoption indexes, album matching,
 * MediaStore DTO conversion, and mirrored subfolder resolution.
 */

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:photo_manager/photo_manager.dart';

import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/services/device_media_scanner.dart';
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/folder_traversal_service.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/utils/app_logger.dart';

/// Video extensions used to classify directory files (no MediaStore here).
const Set<String> _videoExtensions = {
  '.mp4', '.mov', '.mkv', '.avi', '.webm', '.m4v', '.3gp', '.ts', '.mpeg',
  '.mpg',
};

/// Recursively scans a directory rule's source tree into engine DTOs.
///
/// Asset ids are normalized absolute file paths (stable across runs);
/// [BackupAsset.relativePath] is the tree-relative subfolder ending in `/`
/// so the destination can mirror the folder-in-folder structure.
Future<({List<BackupAsset> assets, int skippedUnresolvable})>
    scanBackupDirectory(
  BackupRule rule, {
  required int maxFiles,
}) async {
  final sourcePath = rule.sourcePath;
  if (sourcePath == null || sourcePath.isEmpty) {
    throw StateError('Directory rule "${rule.albumName}" has no source path');
  }
  final root = Directory(sourcePath);
  if (!await root.exists()) {
    throw StateError(
        'Folder "$sourcePath" is missing or inaccessible (storage permission?)');
  }
  final assets = <BackupAsset>[];
  final seenPaths = <String>{};
  var skippedUnresolvable = 0;
  final queue = <Directory>[root];
  final visitedDirs = <String>{};

  while (queue.isNotEmpty && assets.length < maxFiles) {
    final dir = queue.removeAt(0);
    final normalizedDir = p.normalize(dir.path);
    if (!visitedDirs.add(normalizedDir)) continue;
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (e) {
      if (normalizedDir == p.normalize(root.path)) {
        throw StateError(
            'Cannot read folder "$sourcePath" (storage permission?)');
      }
      AppLogger.w('Backup: skipping unreadable dir ${dir.path}: $e',
          tag: 'AutoBackup');
      continue;
    }
    for (final entity in entries) {
      if (entity is Directory) {
        if (rule.mirrorsSubfolders) queue.add(entity);
        continue;
      }
      if (entity is! File) continue;
      final filePath = p.normalize(entity.path);
      if (!seenPaths.add(filePath)) continue;
      try {
        final stat = await entity.stat();
        final relDir = p.relative(p.dirname(filePath), from: sourcePath);
        final relDirPosix =
            relDir == '.' ? '' : '${relDir.replaceAll('\\', '/')}/';
        final title = p.basename(filePath);
        assets.add(BackupAsset(
          assetId: filePath,
          title: title,
          relativePath: relDirPosix,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
          sizeBytes: stat.size,
          isVideo: _videoExtensions
              .contains(p.extension(filePath).toLowerCase()),
        ));
      } catch (_) {
        skippedUnresolvable++;
      }
    }
  }
  return (assets: assets, skippedUnresolvable: skippedUnresolvable);
}

/// Indexes every file in the destination tree by tree-relative path so
/// directory-rule adoption matches the exact subfolder copy (A7).
Map<String, CloudFileRef> cloudTreeFilesByPath(
  HiveService hive,
  String? albumFolderId,
) {
  final map = <String, CloudFileRef>{};
  if (albumFolderId == null) return map;
  final descendants = FolderTraversalService.resolveDescendants(
    targetFolderId: albumFolderId,
    allFolders: hive.allFolders,
    allFiles: hive.allFiles,
  );
  for (final item in descendants) {
    // item.relativePath starts with the sanitized root folder name; strip
    // it so keys match BackupAsset.containerPath (tree-relative).
    final slash = item.relativePath.indexOf('/');
    final key = slash == -1
        ? item.file.name
        : item.relativePath.substring(slash + 1);
    if (map.containsKey(key)) continue;
    map[key] = CloudFileRef(
      fileId: item.file.fileId,
      sizeBytes: (item.file.sizeMb * 1048576).round(),
    );
  }
  return map;
}

/// Indexes existing destination files by name for cloud adoption (A7).
Map<String, CloudFileRef> cloudFilesByName(
  HiveService hive,
  String? albumFolderId,
) {
  final map = <String, CloudFileRef>{};
  if (albumFolderId == null) return map;
  for (final file in hive.filesInFolder(albumFolderId)) {
    if (map.containsKey(file.name)) continue;
    map[file.name] = CloudFileRef(
      fileId: file.fileId,
      sizeBytes: (file.sizeMb * 1048576).round(),
    );
  }
  return map;
}

/// Matches the rule album by exact name, then case-insensitively.
MediaAlbum? findBackupAlbum(List<MediaAlbum> albums, String name) {
  for (final album in albums) {
    if (album.name == name) return album;
  }
  final lower = name.toLowerCase();
  for (final album in albums) {
    if (album.name.toLowerCase() == lower) return album;
  }
  return null;
}

/// Converts one AssetEntity to a DTO; null when metadata is unreadable.
Future<BackupAsset?> backupAssetFromEntity(AssetEntity entity) async {
  try {
    final rawTitle = entity.title;
    final title =
        (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : entity.id;
    final modifiedSec = entity.modifiedDateSecond ?? entity.createDateSecond;
    final modifiedMs =
        (modifiedSec ?? DateTime.now().millisecondsSinceEpoch ~/ 1000) * 1000;
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

/// Resolves `root/Backup/<Album>/<subfolders…>` for one tree-relative
/// directory, creating missing segments idempotently. [cache] memoizes
/// resolved ids for the duration of a run.
Future<Result<String>> resolveBackupSubfolderPath({
  required BackupRule rule,
  required String relativeDir,
  required HiveService hive,
  FileManagerService? files,
  Map<String, String>? cache,
}) async {
  try {
    final rootId = rule.albumFolderId;
    if (rootId == null) {
      return const Failure(
          NotFoundFailure('Backup path missing for subfolder'));
    }
    final normalized =
        p.normalize(relativeDir.trim()).replaceAll('\\', '/');
    if (normalized.isEmpty || normalized == '.') {
      return Success(rootId);
    }
    final cached = cache?[normalized];
    if (cached != null) return Success(cached);
    if (files == null) {
      return const Failure(
          UnknownFailure('FileManager missing for backup folders'));
    }
    var parentId = rootId;
    var walked = '';
    for (final segment in normalized.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      walked = walked.isEmpty ? segment : '$walked/$segment';
      final memo = cache?[walked];
      if (memo != null) {
        parentId = memo;
        continue;
      }
      final sanitized = FolderTraversalService.sanitizeSegment(segment);
      var matches = hive.allFolders
          .where((f) => f.parentId == parentId && f.name == sanitized);
      if (matches.isEmpty) {
        await files.createFolder(sanitized, parentId: parentId);
        matches = hive.allFolders
            .where((f) => f.parentId == parentId && f.name == sanitized);
        if (matches.isEmpty) {
          return Failure(
              UnknownFailure('Could not create backup folder "$sanitized"'));
        }
      }
      parentId = matches.first.id;
      cache?[walked] = parentId;
    }
    cache?[normalized] = parentId;
    return Success(parentId);
  } catch (e) {
    return Failure(UnknownFailure('Backup subfolder setup failed: $e', e));
  }
}