/*
 * File: folder_stats.dart
 * Description: Data model representing recursive item counts and storage size metrics for a folder tree.
 */

/// Encapsulates recursive file count, subfolder count, and aggregate storage size metrics.
class FolderStats {
  /// Total number of files directly in this folder and all nested subfolders.
  final int fileCount;

  /// Total number of nested descendant subfolders (excluding the folder itself).
  final int subfolderCount;

  /// Total storage size in megabytes consumed by all descendant files.
  final double totalSizeMb;

  /// Constructs an immutable FolderStats instance.
  const FolderStats({
    required this.fileCount,
    required this.subfolderCount,
    required this.totalSizeMb,
  });

  /// Formatted storage size string with appropriate magnitude (KB, MB, GB).
  String get formattedSize {
    if (totalSizeMb < 0.001) {
      return '${(totalSizeMb * 1024).toStringAsFixed(1)} KB';
    }
    if (totalSizeMb < 1) {
      return '${(totalSizeMb * 1024).toStringAsFixed(0)} KB';
    }
    if (totalSizeMb >= 1024) {
      return '${(totalSizeMb / 1024).toStringAsFixed(2)} GB';
    }
    return '${totalSizeMb.toStringAsFixed(2)} MB';
  }
}
