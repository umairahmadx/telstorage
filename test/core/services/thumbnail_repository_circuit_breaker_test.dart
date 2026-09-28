/*
 * File: thumbnail_repository_circuit_breaker_test.dart
 * Description: Unit tests validating ThumbnailRepository circuit breaker and quiet offline backoff on connection errors.
 */

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/thumbnail_repository.dart';

class _FakeFailingTelegramService extends Fake implements TelegramService {
  int downloadAttempts = 0;

  @override
  Future<Uint8List> downloadByFileId(String fileId, [dynamic priority]) async {
    downloadAttempts++;
    throw const SocketException("Failed host lookup: 'api.telegram.org'");
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThumbnailRepository Circuit Breaker Tests', () {
    late _FakeFailingTelegramService fakeTelegram;
    late ThumbnailRepository repository;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('thumb_cb_test_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => tempDir.path,
      );
      fakeTelegram = _FakeFailingTelegramService();
      repository = ThumbnailRepository(fakeTelegram);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('TC-THUMB-CB-01: Network failure triggers 30s cooldown and suppresses repeated downloads', () async {
      final file1 = FileRecord(
        fileId: 'file-1',
        name: 'test1.jpg',
        metadataMessageId: 1,
        sizeMb: 1.0,
        mimeType: 'image/jpeg',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'hash-1',
        thumbnailFileId: 'thumb-1',
      );

      final file2 = FileRecord(
        fileId: 'file-2',
        name: 'test2.jpg',
        metadataMessageId: 2,
        sizeMb: 1.0,
        mimeType: 'image/jpeg',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'hash-2',
        thumbnailFileId: 'thumb-2',
      );

      expect(repository.isOfflineCooldown, isFalse);

      // First request fails and trips circuit breaker
      final res1 = await repository.getThumbnailData(file1);
      expect(res1, isNull);
      expect(fakeTelegram.downloadAttempts, equals(1));
      expect(repository.isOfflineCooldown, isTrue);

      // Second request immediately returns null during cooldown without calling network
      final res2 = await repository.getThumbnailData(file2);
      expect(res2, isNull);
      expect(fakeTelegram.downloadAttempts, equals(1));
    });
  });
}
