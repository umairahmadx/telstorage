/*
 * File: lru_folder_cache_test.dart
 * Description: Unit tests for LRU folder cache eviction and partition retrieval.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/folder_partition.dart';
import 'package:telstorage/core/services/lru_folder_cache_service.dart';

void main() {
  group('LruFolderCacheService Tests', () {
    final cache = LruFolderCacheService.instance;

    setUp(() {
      cache.clear();
    });

    test('Store and retrieve folder partition', () {
      final partition = FolderPartition(
        folderId: 'folder_1',
        messageId: 100,
        files: [],
      );

      cache.put('folder_1', partition);
      final retrieved = cache.get('folder_1');

      expect(retrieved, isNotNull);
      expect(retrieved?.folderId, equals('folder_1'));
      expect(retrieved?.messageId, equals(100));
    });

    test('LRU eviction occurs when capacity cap is exceeded', () {
      for (int i = 0; i < LruFolderCacheService.maxCapacity + 5; i++) {
        cache.put(
          'folder_$i',
          FolderPartition(folderId: 'folder_$i', messageId: i, files: []),
        );
      }

      // The total cached count should never exceed maxCapacity (30)
      expect(cache.cachedFolderCount, equals(LruFolderCacheService.maxCapacity));

      // The oldest 5 entries (folder_0 through folder_4) should be evicted
      expect(cache.get('folder_0'), isNull);
      expect(cache.get('folder_4'), isNull);

      // Recent entries should remain
      expect(cache.get('folder_30'), isNotNull);
    });
  });
}
