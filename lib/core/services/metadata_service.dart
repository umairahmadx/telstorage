import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import '../models/app_metadata.dart';
import 'telegram_service.dart';

/// Manages the pinned .metadata.json on Telegram.
///
/// Discovery strategy (in order):
///   1. Local secure storage has a cached file_id → use it (fast path)
///   2. No local cache → ask Telegram for the pinned message → use its file_id
///   3. Nothing pinned → first-time user → create and pin new metadata
///
/// This means any device / browser that logs in with the same bot+channel
/// will always find the same metadata, because the pinned message is global.
class MetadataService {
  final TelegramService _telegram;
  static const _storage = FlutterSecureStorage();

  MetadataService(this._telegram);

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetch current metadata.  Works on any device — no prior local state needed.
  Future<AppMetadata> fetch() async {
    print('📖 [MetadataService] Fetching metadata...');

    // Fast path: we already know the file_id from a previous session
    final cachedFileId = await _storage.read(key: 'metadata_file_id');
    if (cachedFileId != null) {
      print('📖 [MetadataService] Using cached file_id: $cachedFileId');
      return _downloadMeta(cachedFileId);
    }

    // Slow path: discover via the channel's pinned message
    print('📖 [MetadataService] No local cache — checking pinned message...');
    try {
      final pinnedMsgId = await _telegram.getPinnedMessageId();
      final fileId = await _telegram.getFileIdOfMessage(pinnedMsgId);
      print('📖 [MetadataService] Found pinned metadata, file_id: $fileId');

      // Cache it so next startup is fast
      await _storage.write(key: 'metadata_file_id', value: fileId);
      await _storage.write(
        key: 'metadata_message_id',
        value: pinnedMsgId.toString(),
      );

      return _downloadMeta(fileId);
    } catch (e) {
      // No pinned message → first-time setup for this channel
      print('📖 [MetadataService] No pinned message — first-time setup');
      final email = await _storage.read(key: 'email') ?? 'unknown@user.com';
      await initMetadata(email);

      final newFileId = await _storage.read(key: 'metadata_file_id');
      return _downloadMeta(newFileId!);
    }
  }

  /// Replace metadata with updated version (upload + pin + delete old).
  Future<void> update(AppMetadata meta) async {
    final oldMsgId = meta.metadataMessageId;
    meta.lastSynced = DateTime.now();

    print('🔄 [MetadataService] Uploading updated metadata...');
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(meta.toJson())));
    final result =
        await _telegram.uploadBytesWithFileId(bytes, '.metadata.json');
    final newMsgId = result['message_id'] as int;
    final newFileId = result['file_id'] as String;
    print(
      '🔄 [MetadataService] Uploaded → message_id: $newMsgId, '
      'file_id: $newFileId',
    );

    // Pin the new message so any device can discover it
    await _telegram.pinMessage(newMsgId);

    // Persist locally
    await _storage.write(
      key: 'metadata_message_id',
      value: newMsgId.toString(),
    );
    await _storage.write(key: 'metadata_file_id', value: newFileId);

    // Delete old metadata message
    if (oldMsgId > 0) {
      print('🔄 [MetadataService] Deleting old message: $oldMsgId');
      await _telegram.deleteMessage(oldMsgId);
    }

    meta.metadataMessageId = newMsgId;
    print('✅ [MetadataService] Metadata updated successfully');
  }

  /// Add a file to metadata (increment stats + register FileRef for sync).
  Future<void> addFile(AppMetadata meta, Map<String, dynamic> fileData) async {
    meta.totalFiles++;
    meta.storageUsedMb += (fileData['size_mb'] as num).toDouble();

    final mimeType = fileData['mime_type'] as String? ?? '';
    final category = _category(mimeType);
    meta.categories[category]!.count++;
    meta.categories[category]!.sizeMb +=
        (fileData['size_mb'] as num).toDouble();

    // Register FileRef so any device can rebuild Hive from Telegram
    final metaFileId = fileData['metadata_file_id'] as String?;
    if (metaFileId != null && metaFileId.isNotEmpty) {
      meta.files.removeWhere((f) => f.fileId == fileData['file_id']);
      meta.files.add(FileRef(
        fileId: fileData['file_id'] as String,
        metaFileId: metaFileId,
        name: fileData['name'] as String,
        folderId: fileData['folder_id'] as String?,
      ));
    }

    await update(meta);
  }

  /// Remove a file from metadata.
  Future<void> removeFile(
    AppMetadata meta,
    String fileId,
    double sizeMb,
    String mimeType,
  ) async {
    meta.totalFiles = (meta.totalFiles - 1).clamp(0, 999999);
    meta.storageUsedMb =
        (meta.storageUsedMb - sizeMb).clamp(0.0, double.infinity);
    meta.files.removeWhere((f) => f.fileId == fileId);

    final category = _category(mimeType);
    meta.categories[category]!.count =
        (meta.categories[category]!.count - 1).clamp(0, 999999);
    meta.categories[category]!.sizeMb =
        (meta.categories[category]!.sizeMb - sizeMb).clamp(
      0.0,
      double.infinity,
    );

    await update(meta);
  }

  // ── First-time setup ───────────────────────────────────────────────────────

  Future<void> initMetadata(String ownerEmail) async {
    print('🔧 [MetadataService] Initializing metadata for: $ownerEmail');
    final meta = AppMetadata(
      owner: ownerEmail,
      storageLimitMb: AppConstants.defaultStorageLimitMb,
      storageUsedMb: 0,
      totalFiles: 0,
      metadataMessageId: 0,
      folders: [],
      categories: {
        'images': CategoryStat(count: 0, sizeMb: 0),
        'videos': CategoryStat(count: 0, sizeMb: 0),
        'docs': CategoryStat(count: 0, sizeMb: 0),
        'others': CategoryStat(count: 0, sizeMb: 0),
      },
      lastSynced: DateTime.now(),
    );

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(meta.toJson())));
    final result =
        await _telegram.uploadBytesWithFileId(bytes, '.metadata.json');
    final msgId = result['message_id'] as int;
    final fileId = result['file_id'] as String;

    // Pin it so all devices can discover it
    await _telegram.pinMessage(msgId);

    await _storage.write(key: 'metadata_message_id', value: msgId.toString());
    await _storage.write(key: 'metadata_file_id', value: fileId);
    print(
      '✅ [MetadataService] Initialized — message_id: $msgId, '
      'file_id: $fileId',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<AppMetadata> _downloadMeta(String fileId) async {
    print('📖 [MetadataService] Downloading metadata (file_id: $fileId)...');
    final bytes = await _telegram.downloadByFileId(fileId);
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final meta = AppMetadata.fromJson(json);

    // Restore metadataMessageId from secure storage
    final msgIdStr = await _storage.read(key: 'metadata_message_id');
    meta.metadataMessageId = int.tryParse(msgIdStr ?? '') ?? 0;

    print('✅ [MetadataService] Metadata fetched — ${meta.files.length} file(s)');
    return meta;
  }

  String _category(String mimeType) {
    if (mimeType.startsWith('image/')) return 'images';
    if (mimeType.startsWith('video/')) return 'videos';
    if (mimeType == 'application/pdf') return 'docs';
    return 'others';
  }
}
