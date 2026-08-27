/*
 * File: thumbnail_repository_test.dart
 * Description: Unit tests verifying two-tiered LRU memory caching, MRU promotion, capacity eviction, and synchronous byte retrieval in ThumbnailRepository.
 */

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/services/thumbnail_repository.dart';

class FakeTelegramService implements TelegramService {
  @override
  Future<void> init(String token, String channelId) async {}

  @override
  Future<Map<String, dynamic>> uploadBytesWithFileId(
    Uint8List bytes,
    String filename,
  ) async =>
      {'file_id': 'mock_file_id', 'message_id': 1};

  @override
  Future<Uint8List> downloadByFileId(
    String fileId, {
    void Function(double progress)? onProgress,
  }) async =>
      Uint8List(10);

  @override
  Future<void> deleteMessage(int messageId) async {}

  @override
  Future<String> getFileIdOfMessage(int messageId) async => 'mock_id';

  @override
  Future<void> pinMessage(int messageId) async {}

  @override
  Future<int> getPinnedMessageId() async => 1;

  @override
  Future<void> unpinAllMessages() async {}

  @override
  Future<String> getFileIdFromMessage(int messageId) async => 'mock_file_id';
}

void main() {
  late FakeTelegramService fakeTelegram;
  late ThumbnailRepository repository;

  setUp(() {
    fakeTelegram = FakeTelegramService();
    repository = ThumbnailRepository(fakeTelegram);
  });

  group('ThumbnailRepository LRU Memory Cache Tests', () {
    test('TC-01: Synchronously caches and retrieves binary thumbnail bytes',
        () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      repository.addToMemoryCache('file_123', bytes);

      final cached = repository.getMemoryCachedBytes('file_123');
      expect(cached, isNotNull);
      expect(cached, equals(bytes));
      expect(repository.memoryCacheCount, 1);
    });

    test('TC-02: Returns null for cache misses', () {
      final cached = repository.getMemoryCachedBytes('non_existent_file');
      expect(cached, isNull);
    });

    test('TC-03: Evicts oldest entry when maxMemoryCacheSize (200) is exceeded',
        () {
      // Add 200 items (file_0 to file_199)
      for (int i = 0; i < ThumbnailRepository.maxMemoryCacheSize; i++) {
        repository.addToMemoryCache('file_$i', Uint8List.fromList([i]));
      }
      expect(repository.memoryCacheCount, 200);
      expect(repository.getMemoryCachedBytes('file_0'), isNotNull);

      // Add item 201 (should evict the oldest entry)
      // Note: Since file_0 was accessed above, file_1 is now the oldest
      repository.addToMemoryCache('file_200', Uint8List.fromList([200]));
      expect(repository.memoryCacheCount, 200);

      // file_1 should be evicted, file_0 should still exist because it was promoted
      expect(repository.getMemoryCachedBytes('file_1'), isNull);
      expect(repository.getMemoryCachedBytes('file_0'), isNotNull);
      expect(repository.getMemoryCachedBytes('file_200'), isNotNull);
    });

    test('TC-04: Promotes accessed items to Most Recently Used (MRU)', () {
      repository.addToMemoryCache('file_A', Uint8List.fromList([1]));
      repository.addToMemoryCache('file_B', Uint8List.fromList([2]));
      repository.addToMemoryCache('file_C', Uint8List.fromList([3]));

      // Access file_A to promote it to MRU
      repository.getMemoryCachedBytes('file_A');

      // Now order is B (oldest), C, A (newest)
      // Fill to limit to cause 1 eviction
      for (int i = 0; i < ThumbnailRepository.maxMemoryCacheSize - 3; i++) {
        repository.addToMemoryCache('extra_$i', Uint8List.fromList([i]));
      }

      // Add one more to evict oldest (file_B)
      repository.addToMemoryCache('overflow', Uint8List.fromList([99]));

      expect(repository.getMemoryCachedBytes('file_B'), isNull,
          reason: 'file_B was oldest and should be evicted');
      expect(repository.getMemoryCachedBytes('file_A'), isNotNull,
          reason: 'file_A was promoted and should survive');
      expect(repository.getMemoryCachedBytes('file_C'), isNotNull);
    });

    test('TC-05: clearMemoryCache clears all items and resets count', () {
      repository.addToMemoryCache('file_1', Uint8List.fromList([1]));
      repository.addToMemoryCache('file_2', Uint8List.fromList([2]));
      expect(repository.memoryCacheCount, 2);

      repository.clearMemoryCache();
      expect(repository.memoryCacheCount, 0);
      expect(repository.getMemoryCachedBytes('file_1'), isNull);
    });
  });
}
