/*
 * File: browser_filter_helper.dart
 * Description: Utility helper functions for sorting, filtering, and categorization in the Browser ViewModel.
 */

import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'browser_event.dart';

/// Helper methods for sorting and filtering directory files and folders.
abstract final class BrowserFilterHelper {
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
        const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'heic']
            .contains(ext);
    final isVid = mime.startsWith('video/') ||
        const ['mp4', 'mkv', 'mov', 'avi', 'webm', 'flv', 'wmv', 'm4v', '3gp']
            .contains(ext);
    final isDoc = mime == 'application/pdf' ||
        mime.contains('document') ||
        mime.contains('word') ||
        mime.startsWith('text/') ||
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
          'csv'
        ].contains(ext);

    return switch (category) {
      'images' => isImg,
      'videos' => isVid,
      'docs' => isDoc,
      'others' => !isImg && !isVid && !isDoc,
      _ => true,
    };
  }
}
