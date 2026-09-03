/*
 * File: sync_queue_rate_limit_test.dart
 * Description: Unit tests validating SyncQueueService rate-limiting compliance, 429 pause respect, and exponential backoff on repeated failures.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/pending_action.dart';
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/sync_queue_service.dart';
import 'package:telstorage/core/services/telegram_rate_limiter.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/utils/connectivity.dart';

class MockFileManager extends FileManagerService {
  int executeCount = 0;
  bool shouldThrow = false;

  MockFileManager()
      : super(
          MetadataService(TelegramService()),
          TelegramService(),
          HiveService.instance,
        );

  @override
  Future<void> createFolder(String name,
      {String? parentId, String? folderId}) async {
    executeCount++;
    if (shouldThrow) {
      throw Exception('Simulated Telegram 429 error');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<PendingAction> pendingBox;
  late MockFileManager fileManager;
  late SyncQueueService syncQueue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_queue_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(PendingActionAdapter());
    }

    pendingBox = await Hive.openBox<PendingAction>(AppConstants.pendingActionsBox);
    await pendingBox.clear();

    Connectivity.mockConnectionStatus = true;
    TelegramRateLimiter.instance.reset();
    fileManager = MockFileManager();
    syncQueue = SyncQueueService(fileManager);
  });

  tearDown(() async {
    Connectivity.mockConnectionStatus = null;
    syncQueue.dispose();
    await pendingBox.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
    TelegramRateLimiter.instance.reset();
  });

  group('SyncQueueService Rate-Limit & Backoff Tests', () {
    test('TC-01: skips processing when TelegramRateLimiter isPaused is true', () async {
      await pendingBox.put(
        'action-1',
        PendingAction(
          id: 'action-1',
          actionType: AppConstants.actionCreateFolder,
          payload: {'id': 'f1', 'name': 'Folder 1'},
          timestamp: DateTime.now(),
        ),
      );

      TelegramRateLimiter.instance.report429(10);
      expect(TelegramRateLimiter.instance.isPaused, isTrue);

      await syncQueue.processQueue();

      expect(fileManager.executeCount, equals(0),
          reason: 'SyncQueue must not execute actions while Telegram is in a 429 backoff pause');
      expect(pendingBox.length, equals(1));
    });

    test('TC-02: activates backoff on failure and skips subsequent runs unless forced', () async {
      await pendingBox.put(
        'action-fail',
        PendingAction(
          id: 'action-fail',
          actionType: AppConstants.actionCreateFolder,
          payload: {'id': 'f2', 'name': 'Folder Fail'},
          timestamp: DateTime.now(),
        ),
      );

      fileManager.shouldThrow = true;

      // Run 1: should attempt and fail
      await syncQueue.processQueue();
      expect(fileManager.executeCount, equals(1));
      expect(syncQueue.isBackoffActive, isTrue);

      // Run 2: should be skipped due to backoff
      await syncQueue.processQueue();
      expect(fileManager.executeCount, equals(1),
          reason: 'Subsequent run must be skipped due to active exponential backoff');

      // Run 3: force flag bypasses backoff
      await syncQueue.processQueue(force: true);
      expect(fileManager.executeCount, equals(2),
          reason: 'force: true must bypass backoff');
    });

    test('TC-03: resets backoff state when an action succeeds', () async {
      await pendingBox.put(
        'action-success',
        PendingAction(
          id: 'action-success',
          actionType: AppConstants.actionCreateFolder,
          payload: {'id': 'f3', 'name': 'Folder Success'},
          timestamp: DateTime.now(),
        ),
      );

      fileManager.shouldThrow = false;

      await syncQueue.processQueue();

      expect(fileManager.executeCount, equals(1));
      expect(syncQueue.isBackoffActive, isFalse);
      expect(pendingBox.length, equals(0),
          reason: 'Successfully processed action must be deleted from queue');
    });
  });
}
