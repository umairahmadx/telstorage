/// Represents the pinned .metadata.json file on Telegram
/// This is the source of truth for storage stats and folder tree
class AppMetadata {
  final String owner;
  double storageUsedMb;
  int totalFiles;
  int metadataMessageId; // Telegram message_id of this file (for deletion)
  List<Folder> folders;
  List<FileRef> recentFiles; // top 20 recent files for Home screen
  Map<String, int> folderPartitionsMap; // folderId -> partition message_id
  Map<String, CategoryStat> categories;
  DateTime lastSynced;

  AppMetadata({
    required this.owner,
    required this.storageUsedMb,
    required this.totalFiles,
    required this.metadataMessageId,
    required this.folders,
    List<FileRef>? recentFiles,
    Map<String, int>? folderPartitionsMap,
    required this.categories,
    required this.lastSynced,
  })  : recentFiles = recentFiles ?? [],
        folderPartitionsMap = folderPartitionsMap ?? {};

  factory AppMetadata.fromJson(Map<String, dynamic> json) {
    final partitionsMap =
        (json['folder_partitions'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, (v as num).toInt()),
            ) ??
            {};
    return AppMetadata(
      owner: json['owner'] as String,
      storageUsedMb: (json['storage_used_mb'] as num?)?.toDouble() ?? 0.0,
      totalFiles: json['total_files'] as int? ?? 0,
      metadataMessageId: json['metadata_message_id'] as int? ?? 0,
      folders: (json['folders'] as List?)
              ?.map((f) => Folder.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      recentFiles: (json['recent_files'] as List?)
              ?.map((f) => FileRef.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      folderPartitionsMap: partitionsMap,
      categories: () {
        final defaults = {
          'images': CategoryStat(count: 0, sizeMb: 0.0),
          'videos': CategoryStat(count: 0, sizeMb: 0.0),
          'documents': CategoryStat(count: 0, sizeMb: 0.0),
          'audio': CategoryStat(count: 0, sizeMb: 0.0),
          'archives': CategoryStat(count: 0, sizeMb: 0.0),
          'others': CategoryStat(count: 0, sizeMb: 0.0),
        };
        final loaded = (json['categories'] as Map<String, dynamic>?)?.map(
              (key, value) => MapEntry(
                key,
                CategoryStat.fromJson(value as Map<String, dynamic>),
              ),
            ) ??
            {};
        defaults.addAll(loaded);
        return defaults;
      }(),
      lastSynced: DateTime.parse(
          json['last_synced'] as String? ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'owner': owner,
      'storage_used_mb': storageUsedMb,
      'total_files': totalFiles,
      'metadata_message_id': metadataMessageId,
      'folders': folders.map((f) => f.toJson()).toList(),
      'recent_files': recentFiles.take(20).map((f) => f.toJson()).toList(),
      'folder_partitions': folderPartitionsMap,
      'categories':
          categories.map((key, value) => MapEntry(key, value.toJson())),
      'last_synced': lastSynced.toIso8601String(),
    };
  }
}

/// Lightweight file reference stored in partition metadata.
class FileRef {
  final String fileId; // internal UUID
  final String metaFileId; // Telegram file_id of the per-file .json
  final String name;
  final String? folderId;

  final double? sizeMb;
  final String? mimeType;
  final String? uploadedAt;
  final int? chunkCount;
  final String? sha256;
  final int? metadataMessageId;
  final String? thumbnailFileId;

  FileRef({
    required this.fileId,
    required this.metaFileId,
    required this.name,
    this.folderId,
    this.sizeMb,
    this.mimeType,
    this.uploadedAt,
    this.chunkCount,
    this.sha256,
    this.metadataMessageId,
    this.thumbnailFileId,
  });

  factory FileRef.fromJson(Map<String, dynamic> json) {
    return FileRef(
      fileId: json['file_id'] as String,
      metaFileId: json['meta_file_id'] as String,
      name: json['name'] as String,
      folderId: json['folder_id'] as String?,
      sizeMb: (json['size_mb'] as num?)?.toDouble(),
      mimeType: json['mime_type'] as String?,
      uploadedAt: json['uploaded_at'] as String?,
      chunkCount: json['chunk_count'] as int?,
      sha256: json['sha256'] as String?,
      metadataMessageId: json['metadata_message_id'] as int?,
      thumbnailFileId: json['thumbnail_file_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'file_id': fileId,
      'meta_file_id': metaFileId,
      'name': name,
      'folder_id': folderId,
      if (sizeMb != null) 'size_mb': sizeMb,
      if (mimeType != null) 'mime_type': mimeType,
      if (uploadedAt != null) 'uploaded_at': uploadedAt,
      if (chunkCount != null) 'chunk_count': chunkCount,
      if (sha256 != null) 'sha256': sha256,
      if (metadataMessageId != null) 'metadata_message_id': metadataMessageId,
      if (thumbnailFileId != null) 'thumbnail_file_id': thumbnailFileId,
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
