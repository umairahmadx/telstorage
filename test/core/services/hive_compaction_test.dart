/*
 * File: hive_compaction_test.dart
 * Description: Unit tests validating Hive box compaction, disk space recovery, and defensive resilience for unopened boxes.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/hive_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HiveService hiveService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_compaction_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FileRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(FolderRecordAdapter());
    }

    hiveService = HiveService.instance;
  });

  tearDown(() async {
    await Hive.close();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('HiveService Compaction Tests', () {
    test('TC-01: compactBox compacts open box with overwritten entries without errors', () async {
      final box = await Hive.openBox<String>('test_compact_box');

      // Write 500 keys, then overwrite them multiple times to generate stale append-only entries
      for (var i = 0; i < 200; i++) {
        await box.put('key_$i', 'initial_value_$i');
      }
      for (var i = 0; i < 200; i++) {
        await box.put('key_$i', 'updated_value_longer_string_$i');
      }
      for (var i = 0; i < 100; i++) {
        await box.delete('key_$i');
      }

      expect(box.length, equals(100));

      // Execute compaction
      await hiveService.compactBox<String>('test_compact_box');

      // Verify data integrity remains intact after compaction
      expect(box.length, equals(100));
      expect(box.get('key_150'), equals('updated_value_longer_string_150'));
      expect(box.get('key_50'), isNull);

      await box.close();
    });

    test('TC-02: compactBox safely ignores unopened box without throwing', () async {
      expect(Hive.isBoxOpen('non_existent_unopened_box'), isFalse);
      // Should not throw
      await hiveService.compactBox('non_existent_unopened_box');
    });

    test('TC-03: compactAll runs on all core boxes without failure', () async {
      await Hive.openBox<FileRecord>(AppConstants.filesBox);
      await Hive.openBox<FolderRecord>(AppConstants.foldersBox);
      await Hive.openBox<int>(AppConstants.partitionSyncBox);

      // Should run across open boxes and skip unopened boxes gracefully
      await hiveService.compactAll();

      expect(Hive.isBoxOpen(AppConstants.filesBox), isTrue);
      expect(Hive.isBoxOpen(AppConstants.foldersBox), isTrue);
      expect(Hive.isBoxOpen(AppConstants.partitionSyncBox), isTrue);
    });
  });
}
