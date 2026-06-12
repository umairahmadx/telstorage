import 'package:hive/hive.dart';

part 'file_record.g.dart';

/// Hive local model for cached file metadata
@HiveType(typeId: 0)
class FileRecord extends HiveObject {
  @HiveField(0)
  String fileId;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? folderId; // null = root

  @HiveField(3)
  int metadataMessageId; // Telegram message_id of the .json (for deletion)

  @HiveField(9)
  String?
      metadataFileId; // Telegram file_id of the .json (permanent — use for download)

  @HiveField(4)
  double sizeMb;

  @HiveField(5)
  String mimeType;

  @HiveField(6)
  DateTime uploadedAt;

  @HiveField(7)
  int chunkCount;

  @HiveField(8)
  String sha256Hash; // for integrity check

  FileRecord({
    required this.fileId,
    required this.name,
    this.folderId,
    required this.metadataMessageId,
    this.metadataFileId,
    required this.sizeMb,
    required this.mimeType,
    required this.uploadedAt,
    required this.chunkCount,
    required this.sha256Hash,
  });

  factory FileRecord.fromMap(Map<String, dynamic> map) {
    return FileRecord(
      fileId: map['file_id'] as String,
      name: map['name'] as String,
      folderId: map['folder_id'] as String?,
      metadataMessageId: map['metadata_message_id'] as int? ?? 0,
      metadataFileId: map['metadata_file_id'] as String?,
      sizeMb: (map['size_mb'] as num).toDouble(),
      mimeType: map['mime_type'] as String? ?? 'application/octet-stream',
      uploadedAt: DateTime.parse(map['uploaded_at'] as String),
      chunkCount: map['chunk_count'] as int,
      sha256Hash: map['sha256'] as String,
    );
  }

  String get formattedSize {
    if (sizeMb < 0.001) return '${(sizeMb * 1024).toStringAsFixed(1)} KB';
    if (sizeMb < 1) return '${(sizeMb * 1024).toStringAsFixed(0)} KB';
    return '${sizeMb.toStringAsFixed(2)} MB';
  }

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isPdf => mimeType == 'application/pdf';
}
