/*
 * File: thumbnail_lifecycle_deletion_test.dart
 * Description: Unit tests validating JPEG thumbnail caching, fallback resolution, thumbnail_message_id tracking, Telegram thumbnail message deletion, and cache eviction.
 */

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/chunk_resume_service.dart';
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/thumbnail_repository.dart';
import 'package:telstorage/core/utils/thumbnail_helper_native.dart';

class _FakeTelegramService extends TelegramService {
  final List<int> deletedMessageIds = [];
  final Map<int, Map<String, dynamic>> remoteJson = {};

  @override
  Future<void> deleteMessage(int messageId) async {
    deletedMessageIds.add(messageId);
  }

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, [
    dynamic priority,
  ]) async {
    final msg = remoteJson.values.firstWhere(
      (m) => m['metadata_file_id'] == fileId,
      orElse: () => {},
    );
    return Uint8List.fromList(utf8.encode(jsonEncode(msg)));
  }
}

class _FakeMetadataService extends MetadataService {
  _FakeMetadataService(super.telegram);

  @override
  Future<AppMetadata> fetch() async {
    return AppMetadata(
      owner: 'test',
      storageUsedMb: 0.0,
      metadataMessageId: 1,
      lastSynced: DateTime.now(),
      totalFiles: 1,
      folders: [],
      categories: {},
    );
  }

  @override
  Future<void> removeFile(
    AppMetadata meta,
    String fileId,
    double sizeMb,
    String mimeType, {
    String? folderId,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeTelegramService telegram;
  late _FakeMetadataService metadataService;
  late HiveService hiveService;
  late FileManagerService fileManager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('thumb_lifecycle_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FileRecordAdapter());
    }
    await Hive.openBox(AppConstants.uploadChunksBox);
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  setUp(() {
    telegram = _FakeTelegramService();
    metadataService = _FakeMetadataService(telegram);
    hiveService = HiveService.instance;
    fileManager = FileManagerService(metadataService, telegram, hiveService);
  });

  group('Thumbnail Lifecycle & Deletion Tests', () {
    test('ChunkResumeService caches and purges thumbnail message ID', () async {
      final resume = ChunkResumeService.instance;
      const hash = 'test_hash_abc123';

      await resume.saveThumbnailFileId(hash, 'file_id_thumb');
      await resume.saveThumbnailMessageId(hash, 555);

      expect(resume.getCachedThumbnailFileId(hash), 'file_id_thumb');
      expect(resume.getCachedThumbnailMessageId(hash), 555);

      await resume.clearFileCache(hash);
      expect(resume.getCachedThumbnailFileId(hash), isNull);
      expect(resume.getCachedThumbnailMessageId(hash), isNull);
    });

    test('ThumbnailHelper caches as .jpg and deletes from disk', () async {
      const fileId = 'test_file_789';
      final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      final cachedJpg = await ThumbnailHelper.cacheThumbnail(fileId, dummyBytes);
      expect(cachedJpg.endsWith('$fileId.jpg'), isTrue);
      expect(File(cachedJpg).existsSync(), isTrue);

      final resolvedPath = await ThumbnailHelper.cachedThumbnailPath(fileId);
      expect(resolvedPath, cachedJpg);

      // Delete cached thumbnail for fileId
      await ThumbnailHelper.deleteCachedThumbnail(fileId);
      expect(File(cachedJpg).existsSync(), isFalse);
      expect(await ThumbnailHelper.cachedThumbnailPath(fileId), isNull);
    });

    test('ThumbnailRepository evicts from memory and deletes disk file', () async {
      final repo = ThumbnailRepository(telegram);
      const fileId = 'repo_file_001';
      final dummyBytes = Uint8List.fromList([10, 20, 30]);

      repo.addToMemoryCache(fileId, dummyBytes);
      await ThumbnailHelper.cacheThumbnail(fileId, dummyBytes);

      expect(repo.getMemoryCachedBytes(fileId), isNotNull);
      final diskPath = await ThumbnailHelper.cachedThumbnailPath(fileId);
      expect(diskPath, isNotNull);

      await repo.evict(fileId);
      expect(repo.getMemoryCachedBytes(fileId), isNull);
      expect(await ThumbnailHelper.cachedThumbnailPath(fileId), isNull);
    });

    test('FileManager deletes chunk messages, metadata message, and thumbnail message', () async {
      const fileId = 'del_file_999';
      final fileMeta = {
        'file_id': fileId,
        'metadata_message_id': 100,
        'metadata_file_id': 'meta_fid_100',
        'thumbnail_file_id': 'thumb_fid_50',
        'thumbnail_message_id': 50, // The thumbnail sticker/JPEG message
        'chunks': [
          {'index': 0, 'message_id': 101},
          {'index': 1, 'message_id': 102},
        ],
      };

      telegram.remoteJson[100] = fileMeta;

      final fileRecord = FileRecord(
        fileId: fileId,
        name: 'test_doc.pdf',
        metadataMessageId: 100,
        metadataFileId: 'meta_fid_100',
        sizeMb: 2.0,
        mimeType: 'application/pdf',
        uploadedAt: DateTime.now(),
        chunkCount: 2,
        sha256Hash: 'hash999',
        thumbnailFileId: 'thumb_fid_50',
      );

      // Save to Hive
      if (!Hive.isBoxOpen(AppConstants.filesBox)) {
        await Hive.openBox<FileRecord>(AppConstants.filesBox);
      }
      await Hive.box<FileRecord>(AppConstants.filesBox).put(fileId, fileRecord);

      await fileManager.deleteFile(fileId);

      // Verify that all chunks, metadata message, AND thumbnail message were deleted
      expect(telegram.deletedMessageIds, contains(101)); // Chunk 0
      expect(telegram.deletedMessageIds, contains(102)); // Chunk 1
      expect(telegram.deletedMessageIds, contains(100)); // Metadata message
      expect(telegram.deletedMessageIds, contains(50));  // Thumbnail message!
    });
  });
}
