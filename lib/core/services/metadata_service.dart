import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import '../models/app_metadata.dart';
import '../models/folder_partition.dart';
import '../utils/app_logger.dart';
import 'lru_folder_cache_service.dart';
import 'telegram_service.dart';

/// Manages the pinned .metadata.json on Telegram.
class MetadataService {
  final TelegramService _telegram;
  static const _storage = FlutterSecureStorage();
  
  // Mutex lock to prevent parallel upload race conditions on metadata index
  Future<void>? _activeLock;

  MetadataService(this._telegram);

  Future<T> _synchronized<T>(Future<T> Function() action) async {
    final previousLock = _activeLock;
    final completer = Completer<void>();
    _activeLock = completer.future;

    if (previousLock != null) {
      await previousLock.catchError((_) {});
    }

    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Fetch current metadata. Works on any device — no prior local state needed.
  Future<AppMetadata> fetch() async {
    AppLogger.d('Fetching metadata...', tag: 'MetadataService');

    // Fast path: we already know the file_id from a previous session
    final cachedFileId = await _storage.read(key: 'metadata_file_id');
    if (cachedFileId != null) {
      AppLogger.d('Using cached file_id: $cachedFileId',
          tag: 'MetadataService');
      final meta = await _downloadMeta(cachedFileId);
      if (meta.files.isNotEmpty && !meta.isPartitioned) {
        await migrateToPartitionedMetadata(meta);
      }
      return meta;
    }

    // Slow path: discover via the channel's pinned message
    AppLogger.d('No local cache — checking pinned message...',
        tag: 'MetadataService');
    try {
      final pinnedMsgId = await _telegram.getPinnedMessageId();
      final fileId = await _telegram.getFileIdOfMessage(pinnedMsgId);
      AppLogger.d('Found pinned metadata, file_id: $fileId',
          tag: 'MetadataService');

      // Cache it so next startup is fast
      await _storage.write(key: 'metadata_file_id', value: fileId);
      await _storage.write(
        key: 'metadata_message_id',
        value: pinnedMsgId.toString(),
      );

      final meta = await _downloadMeta(fileId);
      if (meta.files.isNotEmpty && !meta.isPartitioned) {
        await migrateToPartitionedMetadata(meta);
      }
      return meta;
    } catch (e) {
      // No pinned message → first-time setup for this channel
      AppLogger.d('No pinned message — first-time setup',
          tag: 'MetadataService');
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

    AppLogger.d('Uploading updated metadata...', tag: 'MetadataService');
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(meta.toJson())));
    final result =
        await _telegram.uploadBytesWithFileId(bytes, '.metadata.json');
    final newMsgId = result['message_id'] as int;
    final newFileId = result['file_id'] as String;
    AppLogger.d('Uploaded → message_id: $newMsgId, file_id: $newFileId',
        tag: 'MetadataService');

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
      AppLogger.d('Deleting old message: $oldMsgId', tag: 'MetadataService');
      await _telegram.deleteMessage(oldMsgId);
    }

    meta.metadataMessageId = newMsgId;
    AppLogger.i('Metadata updated successfully', tag: 'MetadataService');
  }

  /// Add a file to metadata (increment stats + register FileRef for sync).
  Future<void> addFile(AppMetadata meta, Map<String, dynamic> fileData) async {
    await _synchronized(() async {
      final latestMeta = await fetch();
      latestMeta.totalFiles++;
      latestMeta.storageUsedMb += (fileData['size_mb'] as num).toDouble();

      final mimeType = fileData['mime_type'] as String? ?? '';
      final category = _category(mimeType);
      latestMeta.categories[category]!.count++;
      latestMeta.categories[category]!.sizeMb +=
          (fileData['size_mb'] as num).toDouble();

      final metaFileId = fileData['metadata_file_id'] as String?;
      if (metaFileId != null && metaFileId.isNotEmpty) {
        final ref = FileRef(
          fileId: fileData['file_id'] as String,
          metaFileId: metaFileId,
          name: fileData['name'] as String,
          folderId: fileData['folder_id'] as String?,
          sizeMb: (fileData['size_mb'] as num?)?.toDouble(),
          mimeType: fileData['mime_type'] as String?,
          uploadedAt: fileData['uploaded_at'] as String?,
          chunkCount: fileData['chunk_count'] as int?,
          sha256: fileData['sha256'] as String?,
          metadataMessageId: fileData['metadata_message_id'] as int?,
          thumbnailFileId: fileData['thumbnail_file_id'] as String?,
        );
        latestMeta.files.removeWhere((f) => f.fileId == fileData['file_id']);
        latestMeta.files.add(ref);
        latestMeta.recentFiles.removeWhere((f) => f.fileId == fileData['file_id']);
        latestMeta.recentFiles.insert(0, ref);
        if (latestMeta.recentFiles.length > 20) {
          latestMeta.recentFiles = latestMeta.recentFiles.take(20).toList();
        }
      }

      await update(latestMeta);
    });
  }

  /// Add multiple files to metadata in 1 single API call.
  Future<void> addBatchFiles(List<Map<String, dynamic>> filesDataList) async {
    if (filesDataList.isEmpty) return;
    await _synchronized(() async {
      final latestMeta = await fetch();
      final Map<String, List<FileRef>> partitionBatch = {};

      for (final fileData in filesDataList) {
        latestMeta.totalFiles++;
        latestMeta.storageUsedMb += (fileData['size_mb'] as num).toDouble();

        final mimeType = fileData['mime_type'] as String? ?? '';
        final category = _category(mimeType);
        latestMeta.categories[category]!.count++;
        latestMeta.categories[category]!.sizeMb +=
            (fileData['size_mb'] as num).toDouble();

        final metaFileId = fileData['metadata_file_id'] as String?;
        if (metaFileId != null && metaFileId.isNotEmpty) {
          final ref = FileRef(
            fileId: fileData['file_id'] as String,
            metaFileId: metaFileId,
            name: fileData['name'] as String,
            folderId: fileData['folder_id'] as String?,
            sizeMb: (fileData['size_mb'] as num?)?.toDouble(),
            mimeType: fileData['mime_type'] as String?,
            uploadedAt: fileData['uploaded_at'] as String?,
            chunkCount: fileData['chunk_count'] as int?,
            sha256: fileData['sha256'] as String?,
            metadataMessageId: fileData['metadata_message_id'] as int?,
            thumbnailFileId: fileData['thumbnail_file_id'] as String?,
          );

          if (latestMeta.isPartitioned) {
            final fId = ref.folderId ?? 'root';
            partitionBatch.putIfAbsent(fId, () => []).add(ref);
          } else {
            latestMeta.files.removeWhere((f) => f.fileId == fileData['file_id']);
            latestMeta.files.add(ref);
          }

          latestMeta.recentFiles.removeWhere((f) => f.fileId == fileData['file_id']);
          latestMeta.recentFiles.insert(0, ref);
        }
      }

      if (latestMeta.isPartitioned && partitionBatch.isNotEmpty) {
        for (final entry in partitionBatch.entries) {
          await _saveFileRefsToPartitionInternal(latestMeta, entry.key, entry.value);
        }
      }

      if (latestMeta.recentFiles.length > 20) {
        latestMeta.recentFiles = latestMeta.recentFiles.take(20).toList();
      }

      await update(latestMeta);
    });
  }

  /// Update an existing FileRef in partitions/legacy array and recentFiles.
  Future<void> updateFileRef(FileRef ref, {String? oldFolderId}) async {
    await _synchronized(() async {
      final latestMeta = await fetch();
      final newFolderId = ref.folderId ?? 'root';
      final previousFolderId = oldFolderId ?? ref.folderId ?? 'root';

      if (latestMeta.isPartitioned) {
        if (previousFolderId != newFolderId) {
          final oldPartition = await fetchFolderPartition(previousFolderId);
          if (oldPartition != null) {
            final oldFiles = List<FileRef>.from(oldPartition.files)
              ..removeWhere((f) => f.fileId == ref.fileId);
            await _saveFileRefsToPartitionInternal(latestMeta, previousFolderId, oldFiles);
          }
        }
        await _saveFileRefsToPartitionInternal(latestMeta, newFolderId, [ref]);
      } else {
        latestMeta.files.removeWhere((f) => f.fileId == ref.fileId);
        latestMeta.files.add(ref);
      }

      final idx = latestMeta.recentFiles.indexWhere((f) => f.fileId == ref.fileId);
      if (idx != -1) {
        latestMeta.recentFiles[idx] = ref;
      }

      await update(latestMeta);
    });
  }

  /// Add a new FileRef (e.g. from copyFile) updating storage stats and partitions.
  Future<void> addFileRef(FileRef ref, double sizeMb, String mimeType) async {
    await _synchronized(() async {
      final latestMeta = await fetch();
      latestMeta.totalFiles++;
      latestMeta.storageUsedMb += sizeMb;

      final category = _category(mimeType);
      latestMeta.categories[category]!.count++;
      latestMeta.categories[category]!.sizeMb += sizeMb;

      if (latestMeta.isPartitioned) {
        final fId = ref.folderId ?? 'root';
        await _saveFileRefsToPartitionInternal(latestMeta, fId, [ref]);
      } else {
        latestMeta.files.removeWhere((f) => f.fileId == ref.fileId);
        latestMeta.files.add(ref);
      }

      latestMeta.recentFiles.removeWhere((f) => f.fileId == ref.fileId);
      latestMeta.recentFiles.insert(0, ref);
      if (latestMeta.recentFiles.length > 20) {
        latestMeta.recentFiles = latestMeta.recentFiles.take(20).toList();
      }

      await update(latestMeta);
    });
  }

  Future<void> _saveFileRefsToPartitionInternal(
    AppMetadata meta,
    String folderId,
    List<FileRef> newRefs,
  ) async {
    final existingPartition = await fetchFolderPartition(folderId) ??
        FolderPartition(folderId: folderId, messageId: 0, files: []);

    final updatedFiles = List<FileRef>.from(existingPartition.files);
    for (final ref in newRefs) {
      updatedFiles.removeWhere((f) => f.fileId == ref.fileId);
      updatedFiles.add(ref);
    }

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'folder_id': folderId,
      'files': updatedFiles.map((r) => r.toJson()).toList(),
      'updated_at': DateTime.now().toIso8601String(),
    })));

    final result = await _telegram.uploadBytesWithFileId(
      bytes,
      'folder_$folderId.json',
    );
    final msgId = result['message_id'] as int;

    LruFolderCacheService.instance.put(
      folderId,
      FolderPartition(folderId: folderId, messageId: msgId, files: updatedFiles),
    );
    meta.folderPartitionsMap[folderId] = msgId;

    if (existingPartition.messageId > 0) {
      try {
        await _telegram.deleteMessage(existingPartition.messageId);
      } catch (_) {}
    }
  }

  /// Remove a file from metadata.
  Future<void> removeFile(
    AppMetadata meta,
    String fileId,
    double sizeMb,
    String mimeType, {
    String? folderId,
  }) async {
    await _synchronized(() async {
      final latestMeta = await fetch();
      latestMeta.totalFiles = (latestMeta.totalFiles - 1).clamp(0, 999999);
      latestMeta.storageUsedMb =
          (latestMeta.storageUsedMb - sizeMb).clamp(0.0, double.infinity);
      latestMeta.files.removeWhere((f) => f.fileId == fileId);
      latestMeta.recentFiles.removeWhere((f) => f.fileId == fileId);

      if (latestMeta.isPartitioned) {
        final fId = folderId ?? 'root';
        final existingPartition = await fetchFolderPartition(fId);
        if (existingPartition != null) {
          final updatedFiles = List<FileRef>.from(existingPartition.files)
            ..removeWhere((f) => f.fileId == fileId);

          final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
            'folder_id': fId,
            'files': updatedFiles.map((r) => r.toJson()).toList(),
            'updated_at': DateTime.now().toIso8601String(),
          })));

          final result = await _telegram.uploadBytesWithFileId(
            bytes,
            'folder_$fId.json',
          );
          final msgId = result['message_id'] as int;

          LruFolderCacheService.instance.put(
            fId,
            FolderPartition(folderId: fId, messageId: msgId, files: updatedFiles),
          );
          latestMeta.folderPartitionsMap[fId] = msgId;

          if (existingPartition.messageId > 0) {
            try {
              await _telegram.deleteMessage(existingPartition.messageId);
            } catch (_) {}
          }
        }
      }

      final category = _category(mimeType);
      latestMeta.categories[category]!.count =
          (latestMeta.categories[category]!.count - 1).clamp(0, 999999);
      latestMeta.categories[category]!.sizeMb =
          (latestMeta.categories[category]!.sizeMb - sizeMb).clamp(
        0.0,
        double.infinity,
      );

      await update(latestMeta);
    });
  }

  /// Automatically migrates monolithic single central metadata to split folder partitions.
  Future<void> migrateToPartitionedMetadata(AppMetadata meta) async {
    await _synchronized(() async {
      AppLogger.i('Starting migration from single central metadata to folder partitions...',
          tag: 'MetadataService');

      final Map<String, List<FileRef>> folderGroups = {};
      for (final f in meta.files) {
        final fId = f.folderId ?? 'root';
        folderGroups.putIfAbsent(fId, () => []).add(f);
      }

      final Map<String, int> partitionsMap = {};
      for (final entry in folderGroups.entries) {
        final folderId = entry.key;
        final fileRefs = entry.value;
        final partitionJson = {
          'folder_id': folderId,
          'files': fileRefs.map((r) => r.toJson()).toList(),
          'updated_at': DateTime.now().toIso8601String(),
        };

        final bytes = Uint8List.fromList(utf8.encode(jsonEncode(partitionJson)));
        final result =
            await _telegram.uploadBytesWithFileId(bytes, 'folder_$folderId.json');
        final msgId = result['message_id'] as int;
        partitionsMap[folderId] = msgId;

        // Warm up LRU Cache slot
        LruFolderCacheService.instance.put(
          folderId,
          FolderPartition(folderId: folderId, messageId: msgId, files: fileRefs),
        );
      }

      meta.folderPartitionsMap = partitionsMap;
      meta.isPartitioned = true;
      meta.recentFiles = meta.files.take(20).toList();
      meta.files = []; // Strip monolithic file array to keep Master Root Index ~2-5 KB

      await update(meta);
      AppLogger.i(
        'Migration complete: ${folderGroups.length} folder partitions created & pinned Master Root Index updated.',
        tag: 'MetadataService',
      );
    });
  }

  /// Fetch a folder's metadata partition on-demand via LRU cache
  Future<FolderPartition?> fetchFolderPartition(String folderId) async {
    final cached = LruFolderCacheService.instance.get(folderId);
    if (cached != null) return cached;

    final appMeta = await fetch();
    final messageId = appMeta.folderPartitionsMap[folderId];
    if (messageId == null) return null;

    try {
      final fileId = await _telegram.getFileIdOfMessage(messageId);
      final jsonBytes = await _telegram.downloadByFileId(fileId);
      final jsonStr = utf8.decode(jsonBytes);
      final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final partition = FolderPartition.fromJson(jsonMap, messageId);

      LruFolderCacheService.instance.put(folderId, partition);
      return partition;
    } catch (e) {
      AppLogger.e('Failed to fetch folder partition $folderId: $e',
          tag: 'MetadataService');
      return null;
    }
  }

  /// Safely move a file between folders (Append to Dest -> Confirm Write -> Remove from Src)
  Future<void> moveFileBetweenFolders(
    String fileId,
    String srcFolderId,
    String destFolderId,
  ) async {
    await _synchronized(() async {
      final srcPartition = await fetchFolderPartition(srcFolderId);
      final fileRef = srcPartition?.files.firstWhere(
        (f) => f.fileId == fileId,
        orElse: () => throw Exception('File $fileId not found in source partition $srcFolderId'),
      );

      if (fileRef == null) return;

      // Step 1: Append to destination partition FIRST and write to Telegram
      final destPartition = await fetchFolderPartition(destFolderId) ??
          FolderPartition(folderId: destFolderId, messageId: 0, files: []);

      final updatedDestFiles = List<FileRef>.from(destPartition.files)
        ..removeWhere((f) => f.fileId == fileId)
        ..add(fileRef);

      final destBytes = Uint8List.fromList(utf8.encode(jsonEncode({
        'folder_id': destFolderId,
        'files': updatedDestFiles.map((r) => r.toJson()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      })));

      final destResult = await _telegram.uploadBytesWithFileId(
        destBytes,
        'folder_$destFolderId.json',
      );
      final destMsgId = destResult['message_id'] as int;

      LruFolderCacheService.instance.put(
        destFolderId,
        FolderPartition(folderId: destFolderId, messageId: destMsgId, files: updatedDestFiles),
      );
      final appMeta = await fetch();
      appMeta.folderPartitionsMap[destFolderId] = destMsgId;

      if (destPartition.messageId > 0) {
        try {
          await _telegram.deleteMessage(destPartition.messageId);
        } catch (_) {}
      }

      // Step 2: Remove from source partition ONLY after destination write succeeds
      if (srcPartition != null) {
        final updatedSrcFiles = List<FileRef>.from(srcPartition.files)
          ..removeWhere((f) => f.fileId == fileId);

        final srcBytes = Uint8List.fromList(utf8.encode(jsonEncode({
          'folder_id': srcFolderId,
          'files': updatedSrcFiles.map((r) => r.toJson()).toList(),
          'updated_at': DateTime.now().toIso8601String(),
        })));

        final srcResult = await _telegram.uploadBytesWithFileId(
          srcBytes,
          'folder_$srcFolderId.json',
        );
        final srcMsgId = srcResult['message_id'] as int;

        LruFolderCacheService.instance.put(
          srcFolderId,
          FolderPartition(folderId: srcFolderId, messageId: srcMsgId, files: updatedSrcFiles),
        );
        appMeta.folderPartitionsMap[srcFolderId] = srcMsgId;

        if (srcPartition.messageId > 0) {
          try {
            await _telegram.deleteMessage(srcPartition.messageId);
          } catch (_) {}
        }
      }

      await update(appMeta);
      AppLogger.i('Safely moved file $fileId from $srcFolderId to $destFolderId',
          tag: 'MetadataService');
    });
  }

  // ── First-time setup ───────────────────────────────────────────────────────

  Future<void> initMetadata(String ownerEmail) async {
    AppLogger.d('Initializing metadata for: $ownerEmail',
        tag: 'MetadataService');
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
    AppLogger.i('Initialized — message_id: $msgId, file_id: $fileId',
        tag: 'MetadataService');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<AppMetadata> _downloadMeta(String fileId) async {
    AppLogger.d('Downloading metadata (file_id: $fileId)...',
        tag: 'MetadataService');
    final bytes = await _telegram.downloadByFileId(fileId);
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final meta = AppMetadata.fromJson(json);

    // Restore metadataMessageId from secure storage
    final msgIdStr = await _storage.read(key: 'metadata_message_id');
    meta.metadataMessageId = int.tryParse(msgIdStr ?? '') ?? 0;

    AppLogger.d('Metadata fetched — ${meta.files.length} file(s)',
        tag: 'MetadataService');
    return meta;
  }

  String _category(String mimeType) {
    if (mimeType.startsWith('image/')) return 'images';
    if (mimeType.startsWith('video/')) return 'videos';
    if (mimeType == 'application/pdf') return 'docs';
    return 'others';
  }
}
