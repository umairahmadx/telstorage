/*
 * File: lru_folder_cache_service.dart
 * Description: Component and logic definition for lru_folder_cache_service.dart in TelStorage.
 */

import 'dart:collection';
import '../constants/app_constants.dart';
import '../models/folder_partition.dart';
import '../utils/app_logger.dart';

/// LRU Cache Manager for folder metadata partitions with configurable capacity cap
class LruFolderCacheService {
  static final LruFolderCacheService instance =
      LruFolderCacheService._internal();

  static const int maxCapacity = AppConstants.lruFolderCacheCapacity;
  final LinkedHashMap<String, FolderPartition> _cache = LinkedHashMap();

  LruFolderCacheService._internal();

  int get cachedFolderCount => _cache.length;

  /// Retrieve folder partition from LRU cache (moves to MRU position)
  FolderPartition? get(String folderId) {
    if (!_cache.containsKey(folderId)) return null;
    final partition = _cache.remove(folderId)!;
    partition.lastAccessedAt = DateTime.now();
    _cache[folderId] = partition; // Move to MRU (end of LinkedHashMap)
    AppLogger.d('LRU Hit: folder partition "$folderId"', tag: 'LruFolderCache');
    return partition;
  }

  /// Store folder partition in LRU cache (evicts oldest if capacity exceeded)
  void put(String folderId, FolderPartition partition) {
    if (_cache.containsKey(folderId)) {
      _cache.remove(folderId);
    } else if (_cache.length >= maxCapacity) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey); // LRU Eviction of oldest folder partition
      AppLogger.i(
        'LRU Eviction: Cap ($maxCapacity) reached — folder partition "$oldestKey" evicted from local cache',
        tag: 'LruFolderCache',
      );
    }
    partition.lastAccessedAt = DateTime.now();
    _cache[folderId] = partition;
  }

  /// Clear LRU cache (e.g. on logout)
  void clear() {
    _cache.clear();
    AppLogger.d('LRU Cache cleared', tag: 'LruFolderCache');
  }
}
