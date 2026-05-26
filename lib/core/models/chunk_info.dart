/// Represents a single part of an uploaded file.
/// For small files (≤ 45 MB) there is exactly one part with the original name.
/// For large files (> 45 MB) there are multiple zip parts:
///   e.g. video.zip.001, video.zip.002, …
class ChunkInfo {
  final int index;       // 1-based
  final int messageId;   // Telegram message_id (for deletion)
  final String? fileId;  // Telegram file_id (permanent — use for download)
  final double sizeMb;
  final String? partName; // Filename of this part on Telegram channel

  ChunkInfo({
    required this.index,
    required this.messageId,
    this.fileId,
    required this.sizeMb,
    this.partName,
  });

  factory ChunkInfo.fromJson(Map<String, dynamic> json) {
    return ChunkInfo(
      index: json['index'] as int,
      messageId: json['message_id'] as int? ?? 0,
      fileId: json['file_id'] as String?,
      sizeMb: (json['size_mb'] as num).toDouble(),
      partName: json['part_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'message_id': messageId,
      if (fileId != null) 'file_id': fileId,
      'size_mb': sizeMb,
      if (partName != null) 'part_name': partName,
    };
  }
}
