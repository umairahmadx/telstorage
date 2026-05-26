

/// Represents the pinned .metadata.json file on Telegram
/// This is the source of truth for storage stats and folder tree
class AppMetadata {
  final String owner;
  final double storageLimitMb;
  double storageUsedMb;
  int totalFiles;
  int metadataMessageId; // Telegram message_id of this file (for deletion)
  List<Folder> folders;
  List<FileRef> files; // enables first-time re-sync from Telegram
  Map<String, CategoryStat> categories;
  DateTime lastSynced;

  AppMetadata({
    required this.owner,
    required this.storageLimitMb,
    required this.storageUsedMb,
    required this.totalFiles,
    required this.metadataMessageId,
    required this.folders,
    List<FileRef>? files,
    required this.categories,
    required this.lastSynced,
  }) : files = files ?? [];

  factory AppMetadata.fromJson(Map<String, dynamic> json) {
    return AppMetadata(
      owner: json['owner'] as String,
      storageLimitMb: (json['storage_limit_mb'] as num).toDouble(),
      storageUsedMb: (json['storage_used_mb'] as num).toDouble(),
      totalFiles: json['total_files'] as int,
      metadataMessageId: json['metadata_message_id'] as int? ?? 0,
      folders: (json['folders'] as List?)
              ?.map((f) => Folder.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      files: (json['files'] as List?)
              ?.map((f) => FileRef.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      categories: (json['categories'] as Map<String, dynamic>?)?.map(
            (key, value) => MapEntry(
              key,
              CategoryStat.fromJson(value as Map<String, dynamic>),
            ),
          ) ??
          {},
      lastSynced: DateTime.parse(json['last_synced'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'owner': owner,
      'storage_limit_mb': storageLimitMb,
      'storage_used_mb': storageUsedMb,
      'total_files': totalFiles,
      'metadata_message_id': metadataMessageId,
      'folders': folders.map((f) => f.toJson()).toList(),
      'files': files.map((f) => f.toJson()).toList(),
      'categories': categories.map((key, value) => MapEntry(key, value.toJson())),
      'last_synced': lastSynced.toIso8601String(),
    };
  }
}

/// Lightweight file reference stored in the global metadata.
/// Allows rebuilding the local Hive cache from Telegram on first install
/// or after clearing app data.
class FileRef {
  final String fileId;     // our internal UUID
  final String metaFileId; // Telegram file_id of the per-file .json (permanent)
  final String name;
  final String? folderId;

  FileRef({
    required this.fileId,
    required this.metaFileId,
    required this.name,
    this.folderId,
  });

  factory FileRef.fromJson(Map<String, dynamic> json) {
    return FileRef(
      fileId: json['file_id'] as String,
      metaFileId: json['meta_file_id'] as String,
      name: json['name'] as String,
      folderId: json['folder_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_id': fileId,
      'meta_file_id': metaFileId,
      'name': name,
      if (folderId != null) 'folder_id': folderId,
    };
  }
}

class Folder {
  String id; // UUID
  String name;
  String? parentId; // null = root
  DateTime createdAt;

  Folder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
  });

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'] as String,
      name: json['name'] as String,
      parentId: json['parent_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class CategoryStat {
  int count;
  double sizeMb;

  CategoryStat({
    required this.count,
    required this.sizeMb,
  });

  factory CategoryStat.fromJson(Map<String, dynamic> json) {
    return CategoryStat(
      count: json['count'] as int,
      sizeMb: (json['size_mb'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'count': count,
      'size_mb': sizeMb,
    };
  }
}
