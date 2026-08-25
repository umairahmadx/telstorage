/*
 * File: storage_repository_contract.dart
 * Description: Component and logic definition for storage_repository_contract.dart in TelStorage.
 */

import '../../../../core/errors/result.dart';
import '../../../../core/models/file_record.dart';
import '../../../../core/models/folder_record.dart';

import '../../../../core/models/folder_stats.dart';

/// Small read-only capability for browsing and home screens.
abstract interface class StorageReader {
  List<FileRecord> get currentFiles;
  List<FolderRecord> get currentFolders;
  FileRecord? getFile(String fileId);
  FolderRecord? getFolder(String folderId);
  List<FolderRecord> getFolders(String? parentId);
  List<FileRecord> getFiles(String? folderId);
  int getFilesInFolderCount(String folderId);
  FolderStats getFolderStats(String folderId);
}

/// File/folder mutation capability.
abstract interface class StorageWriter {
  Future<Result<String>> createFolder(String name, {String? parentId});
  Future<Result<void>> renameFolder(String folderId, String newName);
  Future<Result<void>> deleteFolder(String folderId);
  Future<void> moveFolder(String folderId, String? newParentId);
  Future<void> copyFolder(String folderId, String? targetParentId);
  Future<Result<void>> renameFile(String fileId, String newName);
  Future<void> moveFile(String fileId, String? newFolderId);
  Future<Result<void>> copyFile(String fileId, String? targetFolderId);
  Future<Result<void>> deleteFile(String fileId);
}

abstract interface class DownloadEnqueuer {
  Future<Result<void>> enqueueDownload(FileRecord file);
}

abstract interface class WebShareEnqueuer {
  Future<Result<void>> enqueueWebShare(
    FileRecord file, {
    String? password,
    int? expiryDays,
    String? vanitySlug,
  });
}

/// Composite contract retained for the concrete repository and legacy callers.
/// Domain clients should depend on the smallest capability they need.
abstract interface class StorageRepositoryContract
    implements StorageReader, StorageWriter, DownloadEnqueuer, WebShareEnqueuer {}
