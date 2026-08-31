/*
 * File: upload_folder_helper.dart
 * Description: Helper for recursively scanning local device directories and queueing tasks with preserved folder hierarchy.
 */

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/models/folder_record.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../storage/domain/repositories/storage_repository_contract.dart';
import 'upload_view_model.dart';

/// Exception thrown when a local directory cannot be read or accessed due to permissions or missing path.
class FolderInaccessibleException implements Exception {
  final String message;
  const FolderInaccessibleException(this.message);

  @override
  String toString() => message;
}

/// Statistics returned after scanning and queueing a local directory structure.
class FolderScanResult {
  final int filesCount;
  final int foldersCount;
  final double totalSizeMb;
  final List<UploadTask> queuedTasks;

  const FolderScanResult({
    required this.filesCount,
    required this.foldersCount,
    required this.totalSizeMb,
    required this.queuedTasks,
  });
}

/// Discovers files and subdirectories within a local filesystem path, generates matching
/// FolderRecord hierarchy in TelStorage, and creates lightweight path-backed UploadTask items.
abstract final class UploadFolderHelper {
  /// Scans [dirPath] on device, creates corresponding folders in [storageRepository],
  /// and queues all discovered files into [uploadBloc].
  static Future<FolderScanResult> scanAndQueueFolder({
    required String dirPath,
    required String? targetParentFolderId,
    required StorageRepositoryContract storageRepository,
    required UploadBloc uploadBloc,
  }) async {
    final rootDir = Directory(dirPath);
    if (!await rootDir.exists()) {
      throw const FolderInaccessibleException(
        'Selected folder does not exist or is inaccessible on this device.',
      );
    }

    final rootDirName = p.basename(rootDir.path);
    final String cleanRootName =
        rootDirName.isEmpty ? 'Uploaded Folder' : rootDirName;

    // Discover directories and files via resilient queue-based traversal
    final discoveredDirectories = <Directory>[];
    final discoveredFiles = <File>[];
    final visitedPaths = <String>{};
    final queue = <Directory>[rootDir];
    bool rootReadSuccess = false;

    while (queue.isNotEmpty) {
      final currentDir = queue.removeAt(0);
      final currentNormalized = p.normalize(currentDir.path);
      if (visitedPaths.contains(currentNormalized)) continue;
      visitedPaths.add(currentNormalized);

      try {
        final stream = currentDir.list(followLinks: false);
        await for (final entity in stream) {
          if (entity is Directory) {
            discoveredDirectories.add(entity);
            queue.add(entity);
          } else if (entity is File) {
            discoveredFiles.add(entity);
          } else if (entity is Link) {
            try {
              final targetType = await FileSystemEntity.type(entity.path);
              if (targetType == FileSystemEntityType.file) {
                discoveredFiles.add(File(entity.path));
              } else if (targetType == FileSystemEntityType.directory) {
                final targetDir = Directory(entity.path);
                discoveredDirectories.add(targetDir);
                queue.add(targetDir);
              }
            } catch (_) {}
          }
        }
        if (currentDir.path == rootDir.path) {
          rootReadSuccess = true;
        }
      } on FileSystemException catch (e) {
        AppLogger.w(
          'Directory traversal restricted for ${currentDir.path}: $e',
          tag: 'UploadFolderHelper',
        );
        if (currentDir.path == rootDir.path && !rootReadSuccess) {
          throw const FolderInaccessibleException(
            'Unable to read folder contents due to OS storage restrictions. Please grant storage access or select an accessible folder.',
          );
        }
      } catch (e) {
        AppLogger.w(
          'Unexpected error reading directory ${currentDir.path}: $e',
          tag: 'UploadFolderHelper',
        );
      }
    }

    // Step 1: Create or find root folder in TelStorage
    final existingRootFolders =
        storageRepository.getFolders(targetParentFolderId);
    final existingRoot = existingRootFolders
        .cast<FolderRecord?>()
        .firstWhere((f) => f?.name == cleanRootName, orElse: () => null);

    String rootFolderId;
    if (existingRoot != null) {
      rootFolderId = existingRoot.id;
    } else {
      final createRes = await storageRepository.createFolder(
        cleanRootName,
        parentId: targetParentFolderId,
      );
      if (createRes is Success<String>) {
        rootFolderId = createRes.data;
      } else {
        throw FolderInaccessibleException(
          'Failed to create destination folder in TelStorage: ${createRes.failureOrNull?.message ?? "Unknown error"}',
        );
      }
    }

    // Map of normalized relative directory path -> TelStorage folder ID
    final Map<String, String> dirPathToFolderId = {
      '': rootFolderId,
      '.': rootFolderId,
    };

    int foldersCreated = 1;

    // Step 2: Sort subdirectories by depth so parent directories are created first
    discoveredDirectories.sort((a, b) {
      final relA = p.relative(a.path, from: dirPath);
      final relB = p.relative(b.path, from: dirPath);
      return relA.length.compareTo(relB.length);
    });

    for (final subDir in discoveredDirectories) {
      final relPath = p.relative(subDir.path, from: dirPath);
      final normalizedRelPath = p.normalize(relPath).replaceAll('\\', '/');

      if (normalizedRelPath.isEmpty || normalizedRelPath == '.') continue;

      final parentRelPath = p.dirname(normalizedRelPath);
      final parentNormalized = parentRelPath == '.' ? '' : parentRelPath;
      final parentFolderId =
          dirPathToFolderId[parentNormalized] ?? rootFolderId;
      final folderName = p.basename(normalizedRelPath);

      // Check if folder already exists in TelStorage or create it
      final existingChildren = storageRepository.getFolders(parentFolderId);
      final existingMatch = existingChildren
          .cast<FolderRecord?>()
          .firstWhere((f) => f?.name == folderName, orElse: () => null);

      if (existingMatch != null) {
        dirPathToFolderId[normalizedRelPath] = existingMatch.id;
      } else {
        final res = await storageRepository.createFolder(
          folderName,
          parentId: parentFolderId,
        );
        if (res is Success<String>) {
          dirPathToFolderId[normalizedRelPath] = res.data;
          foldersCreated++;
        }
      }
    }

    // Step 3: Build path-backed UploadTask instances (isTemporaryCacheFile: false)
    int totalSizeBytes = 0;
    final List<UploadTask> tasks = [];

    for (final file in discoveredFiles) {
      final relDirPath = p.relative(p.dirname(file.path), from: dirPath);
      final normalizedRelDirPath =
          p.normalize(relDirPath).replaceAll('\\', '/');
      final targetFolderId =
          dirPathToFolderId[normalizedRelDirPath == '.' ? '' : normalizedRelDirPath] ??
              rootFolderId;

      int fileSize = 0;
      try {
        fileSize = await file.length();
      } catch (_) {}
      totalSizeBytes += fileSize;

      tasks.add(
        UploadTask(
          id: 'upload_${const Uuid().v4()}',
          path: file.path,
          name: p.basename(file.path),
          size: fileSize,
          folderId: targetFolderId,
          isTemporaryCacheFile: false, // Strict: Never delete user original files
        ),
      );
    }

    // Step 4: Queue tasks into UploadBloc
    if (tasks.isNotEmpty) {
      uploadBloc.add(AddUploads(tasks));
    }

    return FolderScanResult(
      filesCount: tasks.length,
      foldersCount: foldersCreated,
      totalSizeMb: totalSizeBytes / (1024 * 1024),
      queuedTasks: tasks,
    );
  }
}
