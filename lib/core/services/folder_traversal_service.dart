/*
 * File: folder_traversal_service.dart
 * Description: Service for recursive Breadth-First Search (BFS) folder traversal, cycle detection, path sanitization, and descendant file resolution.
 */

import 'package:path/path.dart' as p;
import '../models/file_record.dart';
import '../models/folder_record.dart';

/// Represents a resolved file with its relative folder path within a tree.
class FolderFileItem {
  /// The underlying FileRecord.
  final FileRecord file;

  /// Relative path within the folder structure (e.g., 'Work/Invoices/file.pdf').
  final String relativePath;

  /// Subfolder directory without the filename (e.g., 'Work/Invoices').
  final String subpath;

  const FolderFileItem({
    required this.file,
    required this.relativePath,
    required this.subpath,
  });
}

/// Service for calculating descendant hierarchies and aggregate statistics.
abstract final class FolderTraversalService {
  /// Sanitizes a folder or file name segment to prevent directory traversal and illegal OS characters.
  static String sanitizeSegment(String name) {
    var clean = name
        .trim()
        .replaceAll('..', '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    while (clean.startsWith('_') ||
        clean.startsWith('.') ||
        clean.startsWith(' ')) {
      clean = clean.substring(1).trim();
    }
    while (clean.endsWith('_') || clean.endsWith('.') || clean.endsWith(' ')) {
      clean = clean.substring(0, clean.length - 1).trim();
    }

    return clean.isEmpty ? 'unnamed' : clean;
  }

  /// Resolves all descendant files inside [targetFolderId] recursively via BFS.
  ///
  /// Includes:
  /// - Cycle detection (prevents infinite loops if folder hierarchy contains loops)
  /// - Path segment sanitization (strips `..` and illegal OS characters)
  /// - Safe handling of non-existent folder IDs and empty folders
  static List<FolderFileItem> resolveDescendants({
    required String targetFolderId,
    required List<FolderRecord> allFolders,
    required List<FileRecord> allFiles,
  }) {
    final folderMap = {for (final f in allFolders) f.id: f};
    final rootFolder = folderMap[targetFolderId];
    if (rootFolder == null) return const [];

    final rootName = sanitizeSegment(rootFolder.name);
    final results = <FolderFileItem>[];
    final visitedFolderIds = <String>{};

    // Queue holds (folderId, accumulatedPathPrefix)
    final queue = <({String id, String path})>[
      (id: targetFolderId, path: rootName),
    ];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);

      // Cycle detection: skip if already visited in this traversal
      if (!visitedFolderIds.add(current.id)) {
        continue;
      }

      // Add direct child files of current folder
      final childFiles = allFiles.where((f) => f.folderId == current.id);
      for (final file in childFiles) {
        final cleanFileName = sanitizeSegment(file.name);
        results.add(FolderFileItem(
          file: file,
          relativePath: p.posix.join(current.path, cleanFileName),
          subpath: current.path,
        ));
      }

      // Enqueue child subfolders
      final childFolders = allFolders.where((f) => f.parentId == current.id);
      for (final folder in childFolders) {
        if (!visitedFolderIds.contains(folder.id)) {
          final cleanFolderName = sanitizeSegment(folder.name);
          queue.add((
            id: folder.id,
            path: p.posix.join(current.path, cleanFolderName),
          ));
        }
      }
    }

    return results;
  }

  /// Resolves all files selected directly and all files inside selected folders with deduplication.
  static List<FolderFileItem> resolveMultiSelection({
    required Set<String> folderIds,
    required Set<String> fileIds,
    required List<FolderRecord> allFolders,
    required List<FileRecord> allFiles,
  }) {
    final results = <FolderFileItem>[];
    final addedFileIds = <String>{};

    // 1. Direct file selections
    for (final file in allFiles.where((f) => fileIds.contains(f.fileId))) {
      results.add(FolderFileItem(
        file: file,
        relativePath: sanitizeSegment(file.name),
        subpath: '',
      ));
      addedFileIds.add(file.fileId);
    }

    // 2. Folder selections (recursive)
    for (final folderId in folderIds) {
      final descendants = resolveDescendants(
        targetFolderId: folderId,
        allFolders: allFolders,
        allFiles: allFiles,
      );
      for (final item in descendants) {
        if (!addedFileIds.contains(item.file.fileId)) {
          results.add(item);
          addedFileIds.add(item.file.fileId);
        }
      }
    }

    return results;
  }

  /// Computes aggregate statistics (total file count and total size in MB).
  static ({int totalFiles, double totalSizeMb}) calculateStats(
    List<FolderFileItem> items,
  ) {
    var size = 0.0;
    for (final item in items) {
      size += item.file.sizeMb;
    }
    return (totalFiles: items.length, totalSizeMb: size);
  }
}
