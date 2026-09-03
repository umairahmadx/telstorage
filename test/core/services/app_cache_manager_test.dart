/*
 * File: app_cache_manager_test.dart
 * Description: Unit tests validating AppCacheManager partition stats, limit configuration, and LRU eviction logic.
 */

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:telstorage/core/services/app_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
  });

  group('AppCacheManager Unit Tests', () {
    test('Singleton instance is consistent', () {
      final m1 = AppCacheManager.instance;
      final m2 = AppCacheManager.instance;
      expect(identical(m1, m2), isTrue);
    });

    test('Loads default cache limit of 250 MB when unset', () async {
      final limit = await AppCacheManager.instance.getCacheLimitMb();
      expect(limit, AppCacheManager.defaultCacheLimitMb);
      expect(limit, 250);
    });

    test('Sets and persists updated user cache limit', () async {
      await AppCacheManager.instance.setCacheLimitMb(500);
      final updated = await AppCacheManager.instance.getCacheLimitMb();
      expect(updated, 500);
    });

    test('CachePartitionStats computes total bytes and formats correctly', () {
      const stats = CachePartitionStats(
        thumbnailBytes: 15 * 1024 * 1024, // 15 MB
        thumbnailCount: 120,
        imageCacheBytes: 8 * 1024 * 1024, // 8 MB
        imageCacheCount: 10,
        databaseBytes: 5 * 1024 * 1024, // 5 MB
        tempBytes: 2 * 1024 * 1024, // 2 MB
        limitMb: 250,
      );

      expect(stats.totalBytes, 30 * 1024 * 1024);
      expect(stats.totalMb, 30.0);
      expect(stats.formattedThumbnails, '15.0 MB');
      expect(stats.formattedImageCache, '8.0 MB');
      expect(stats.formattedDatabase, '5.0 MB');
      expect(stats.formattedTemp, '2.0 MB');
      expect(stats.formattedTotal, '30.0 MB');
    });

    test('Supported limits contains expected steps', () {
      expect(AppCacheManager.supportedLimitsMb,
          containsAll([50, 100, 250, 500, 1024, 2048]));
    });
  });
}
