/// File: folder_partition.dart
/// Description: Component and logic definition for folder_partition.dart in TelStorage.
library;

import 'app_metadata.dart';

/// Represents a single folder's metadata partition (stored in folder_<id>.json)
class FolderPartition {
  final String folderId;
  final int messageId; // Telegram message_id of this partition file
  final List<FileRef> files;
  DateTime lastAccessedAt;

  FolderPartition({
    required this.folderId,
    required this.messageId,
    required this.files,
    DateTime? lastAccessedAt,
  }) : lastAccessedAt = lastAccessedAt ?? DateTime.now();

  factory FolderPartition.fromJson(Map<String, dynamic> json, int messageId) {
    return FolderPartition(
      folderId: json['folder_id'] as String? ?? 'root',
      messageId: messageId,
      files: (json['files'] as List?)
              ?.map((f) => FileRef.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'folder_id': folderId,
      'files': files.map((f) => f.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}
