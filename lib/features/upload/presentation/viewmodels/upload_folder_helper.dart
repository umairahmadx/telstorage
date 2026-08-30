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

    final List<File> discoveredFiles = [];
    int foldersCreated = 1;

    // Step 2: Traverse directory recursively with strict FileSystemException guard
    try {
      final entities = await rootDir
          .list(recursive: true, followLinks: false)
          .toList();

      // First sort entities: directories before files to ensure parents are created first
      final directories = entities.whereType<Directory>().toList();
      final files = entities.whereType<File>().toList();

      for (final subDir in directories) {
        final relPath = p.relative(subDir.path, from: dirPath);
        final normalizedRelPath = p.normalize(relPath).replaceAll('\\', '/');

        if (normalizedRelPath.isEmpty || normalizedRelPath == '.') continue;

        final parentRelPath = p.dirname(normalizedRelPath);
        final parentNormalized = parentRelPath == '.' ? '' : parentRelPath;
        final parentFolderId =
            dirPathToFolderId[parentNormalized] ?? rootFolderId;
        final folderName = p.basename(normalizedRelPath);

        // Check if folder exists or create it
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

      discoveredFiles.addAll(files);
    } on FileSystemException catch (e) {
      AppLogger.w('Directory traversal restricted by OS permissions: $e',
          tag: 'UploadFolderHelper');
      throw const FolderInaccessibleException(
        'Unable to read folder contents due to OS storage restrictions. Please pick files directly or select an accessible folder.',
      );
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

      final fileSize = await file.length();
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
