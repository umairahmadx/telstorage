/*
 * File: download_conflict_policy.dart
 * Description: Enum defining conflict resolution policies for file downloads.
 */

/// Policy defining how file write collisions are resolved.
enum DownloadConflictPolicy {
  /// Check and prompt user if conflict exists (UI layer default).
  prompt,

  /// Atomically overwrite existing physical file on disk via temp-file staging.
  overwrite,

  /// Dynamically compute a non-colliding filename (e.g. `file (1).ext`) at exact moment of disk save.
  keepBoth,

  /// Skip downloading if target file already exists.
  skip,
}
