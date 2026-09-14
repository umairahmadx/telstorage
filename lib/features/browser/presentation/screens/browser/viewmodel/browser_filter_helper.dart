/*
 * File: browser_filter_helper.dart
 * Description: Utility helper functions for sorting, filtering, and categorization in the Browser ViewModel.
 */

import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/utils/app_mime_helper.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';
import 'package:telstorage/features/storage/data/repositories/storage_repository.dart';
import 'browser_event.dart';

/// Helper methods for sorting and filtering directory files and folders.
abstract final class BrowserFilterHelper {
  /// Queries repository, applies category, search filtering, and sorting.
  static ({
    List<FolderRecord> folders,
    List<FileRecord> files,
    Map<String, int> folderItemCounts,
  }) loadAndFilterContents({
    required StorageRepositoryContract repository,
    required String? folderId,
    required String? category,
    required String searchQuery,
    required BrowserSortOption sortOption,
    required bool sortAscending,
  }) {
    List<FolderRecord> rawFolders = [];
    List<FileRecord> rawFiles = [];

    if (category != null) {
      rawFiles = repository
          .getFiles(folderId)
          .where((f) => matchesCategory(f, category))
          .toList();
      rawFolders = [];
    } else {
      rawFolders = repository.getFolders(folderId);
      rawFiles = repository.getFiles(folderId);
    }

    final q = searchQuery.toLowerCase();
    if (q.isNotEmpty) {
      rawFolders =
          rawFolders.where((f) => f.name.toLowerCase().contains(q)).toList();
      rawFiles =
          rawFiles.where((f) => f.name.toLowerCase().contains(q)).toList();
    }

    sortItems(rawFolders, rawFiles, sortOption, sortAscending);

    final Map<String, int> counts = {};
    for (final f in rawFolders) {
      final isSynced = repository is StorageRepository
          ? repository.isFolderPartitionSynced(f.id)
          : true;
      final localCount = repository.getFilesInFolderCount(f.id);
      counts[f.id] =
          isSynced ? localCount : (localCount > 0 ? localCount : f.itemCount);
    }

    return (
      folders: rawFolders,
      files: rawFiles,
      folderItemCounts: counts,
    );
  }

  /// Sorts folders and files based on criteria and sort order.
  static void sortItems(
    List<FolderRecord> folders,
    List<FileRecord> files,
    BrowserSortOption option,
    bool ascending,
  ) {
    final m = ascending ? 1 : -1;
    switch (option) {
      case BrowserSortOption.name:
        folders.sort(
            (a, b) => m * a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        files.sort(
            (a, b) => m * a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case BrowserSortOption.date:
        folders.sort((a, b) => m * a.createdAt.compareTo(b.createdAt));
        files.sort((a, b) => m * a.uploadedAt.compareTo(b.uploadedAt));
      case BrowserSortOption.size:
        files.sort((a, b) => m * a.sizeMb.compareTo(b.sizeMb));
    }
  }

  /// Checks if file matches media category filter.
  static bool matchesCategory(FileRecord file, String category) {
    final mime = file.mimeType.toLowerCase();
    final ext =
        file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';

    final isImg = mime.startsWith('image/') ||
        AppMimeHelper.allImageExtensions.contains(ext);

    final isVid = mime.startsWith('video/') ||
        const [
          'mp4',
          'mkv',
          'mov',
          'avi',
          'webm',
          'flv',
          'wmv',
          'm4v',
          '3gp',
          'ts',
        ].contains(ext);

    final isAud = mime.startsWith('audio/') ||
        const [
          'mp3',
          'wav',
          'ogg',
          'm4a',
          'flac',
          'aac',
          'opus',
          'wma',
          'aiff',
          'alac',
        ].contains(ext);

    final isDoc = mime == 'application/pdf' ||
        mime.contains('document') ||
        mime.contains('word') ||
        mime.contains('sheet') ||
        mime.contains('presentation') ||
        mime.startsWith('text/') ||
        mime == 'application/rtf' ||
        const [
          'pdf',
          'doc',
          'docx',
          'txt',
          'rtf',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'csv',
          'odt',
          'ods',
          'odp',
          'md',
        ].contains(ext);

    final isArc = mime.contains('zip') ||
        mime.contains('compressed') ||
        mime.contains('tar') ||
        mime.contains('rar') ||
        mime.contains('7z') ||
        mime == 'application/x-tar' ||
        mime == 'application/x-7z-compressed' ||
        mime == 'application/x-rar-compressed' ||
        mime == 'application/x-bzip2' ||
        mime == 'application/x-gzip' ||
        const [
          'zip',
          'rar',
          '7z',
          'tar',
          'gz',
          'bz2',
          'xz',
          'iso',
          'tgz',
        ].contains(ext);

    return switch (category.toLowerCase()) {
      'image' || 'images' => isImg,
      'video' || 'videos' => isVid,
      'audio' => isAud,
      'document' || 'documents' || 'docs' || 'doc' => isDoc,
      'archive' || 'archives' => isArc,
      'others' => !isImg && !isVid && !isAud && !isDoc && !isArc,
      _ => true,
    };
  }
}
