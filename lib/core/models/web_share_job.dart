/// In-memory model representing a public share job on storage.to.
/// Persisted in Hive as a Map<dynamic, dynamic>.
class WebShareJob {
  final String fileId;
  final String name;
  final String mimeType;
  final double sizeMb;
  final double progress;
  final String
      status; // 'queued', 'downloading', 'uploading', 'completed', 'failed'
  final String? shareUrl;
  final String? ownerToken;
  final String? storageToId;
  final String? error;
  final DateTime addedAt;
  final DateTime? completedAt;
  final String? password;
  final int? maxDownloads;
  final int? expiryDays;

  WebShareJob({
    required this.fileId,
    required this.name,
    required this.mimeType,
    required this.sizeMb,
    this.progress = 0.0,
    required this.status,
    this.shareUrl,
    this.ownerToken,
    this.storageToId,
    this.error,
    required this.addedAt,
    this.completedAt,
    this.password,
    this.maxDownloads,
    this.expiryDays,
  });

  bool get isComplete => status == 'completed';
  bool get isUploading => status == 'uploading';
  bool get isDownloading => status == 'downloading';
  bool get isQueued => status == 'queued';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';

  /// Create a copy of the job with optional updated fields.
  WebShareJob copyWith({
    double? progress,
    String? status,
    String? shareUrl,
    String? ownerToken,
    String? storageToId,
    String? error,
    bool clearError = false,
    DateTime? completedAt,
    String? password,
    int? maxDownloads,
    int? expiryDays,
  }) {
    return WebShareJob(
      fileId: fileId,
      name: name,
      mimeType: mimeType,
      sizeMb: sizeMb,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      shareUrl: shareUrl ?? this.shareUrl,
      ownerToken: ownerToken ?? this.ownerToken,
      storageToId: storageToId ?? this.storageToId,
      error: clearError ? null : error ?? this.error,
      addedAt: addedAt,
      completedAt: completedAt ?? this.completedAt,
      password: password ?? this.password,
      maxDownloads: maxDownloads ?? this.maxDownloads,
      expiryDays: expiryDays ?? this.expiryDays,
    );
  }

  /// Serialize to a simple Map for Hive storage.
  Map<String, dynamic> toMap() {
    return {
      'file_id': fileId,
      'name': name,
      'mime_type': mimeType,
      'size_mb': sizeMb,
      'progress': progress,
      'status': status,
      if (shareUrl != null) 'share_url': shareUrl,
      if (ownerToken != null) 'owner_token': ownerToken,
      if (storageToId != null) 'storage_to_id': storageToId,
      if (error != null) 'error': error,
      'added_at': addedAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      if (password != null) 'password': password,
      if (maxDownloads != null) 'max_downloads': maxDownloads,
      if (expiryDays != null) 'expiry_days': expiryDays,
    };
  }

  /// Deserialize from Map.
  factory WebShareJob.fromMap(Map<dynamic, dynamic> map) {
    return WebShareJob(
      fileId: map['file_id'] as String,
      name: map['name'] as String,
      mimeType: map['mime_type'] as String,
      sizeMb: (map['size_mb'] as num).toDouble(),
      progress: (map['progress'] as num? ?? 0.0).toDouble(),
      status: map['status'] as String? ?? 'queued',
      shareUrl: map['share_url'] as String?,
      ownerToken: map['owner_token'] as String?,
      storageToId: map['storage_to_id'] as String?,
      error: map['error'] as String?,
      addedAt: DateTime.parse(map['added_at'] as String),
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
      password: map['password'] as String?,
      maxDownloads: map['max_downloads'] as int?,
      expiryDays: map['expiry_days'] as int?,
    );
  }
}
