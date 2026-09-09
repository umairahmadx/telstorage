/*
 * File: sync_queue_batch_test.dart
 * Description: Unit tests validating contiguous metadata batching, recordLog, and forced queue processing in SyncQueueService.
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

class MockBatchMetadataService extends MetadataService {
  int addBatchCalls = 0;
  List<Map<String, dynamic>> lastBatchList = [];

  MockBatchMetadataService() : super(TelegramService());

  @override
  Future<void> addBatchFiles(List<Map<String, dynamic>> filesDataList) async {
    addBatchCalls++;
    lastBatchList = List.from(filesDataList);
  }
}

class MockBatchFileManager extends FileManagerService {
  final MockBatchMetadataService mockMetaService;

  MockBatchFileManager(this.mockMetaService)
      : super(
          mockMetaService,
          TelegramService(),
          HiveService.instance,
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<PendingAction> pendingBox;
  late MockBatchMetadataService mockMeta;
  late MockBatchFileManager fileManager;
  late SyncQueueService syncQueue;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_batch_test_');
    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(3)) {
      Hive.registerAdapter(PendingActionAdapter());
    }

    pendingBox =
        await Hive.openBox<PendingAction>(AppConstants.pendingActionsBox);
    await pendingBox.clear();

    Connectivity.mockConnectionStatus = true;
    TelegramRateLimiter.instance.reset();
    mockMeta = MockBatchMetadataService();
    fileManager = MockBatchFileManager(mockMeta);
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

  group('SyncQueueService Batch Processing Tests', () {
    test('TC-01: recordLog appends or updates log items in logsNotifier', () {
      final log1 = SyncLogItem(
        id: 'log-1',
        actionType: 'test',
        description: 'Test action',
        timestamp: DateTime.now(),
        status: 'syncing',
      );
      syncQueue.recordLog(log1);
      expect(syncQueue.logsNotifier.value.length, equals(1));
      expect(syncQueue.logsNotifier.value.first.status, equals('syncing'));

      final log1Updated = SyncLogItem(
        id: 'log-1',
        actionType: 'test',
        description: 'Test action completed',
        timestamp: DateTime.now(),
        status: 'completed',
      );
      syncQueue.recordLog(log1Updated);
      expect(syncQueue.logsNotifier.value.length, equals(1));
      expect(syncQueue.logsNotifier.value.first.status, equals('completed'));
    });

    test(
        'TC-02: batches contiguous actionAddFileMeta items into 1 addBatchFiles call',
        () async {
      await pendingBox.put(
        'add-1',
        PendingAction(
          id: 'add-1',
          actionType: AppConstants.actionAddFileMeta,
          payload: {
            'fileMeta': {'file_id': 'f1', 'name': 'file1.txt', 'size_mb': 1.0}
          },
          timestamp: DateTime.now(),
        ),
      );
      await pendingBox.put(
        'add-2',
        PendingAction(
          id: 'add-2',
          actionType: AppConstants.actionAddFileMeta,
          payload: {
            'fileMeta': {'file_id': 'f2', 'name': 'file2.txt', 'size_mb': 2.0}
          },
          timestamp: DateTime.now().add(const Duration(milliseconds: 10)),
        ),
      );
      await pendingBox.put(
        'add-3',
        PendingAction(
          id: 'add-3',
          actionType: AppConstants.actionAddFileMeta,
          payload: {
            'fileMeta': {'file_id': 'f3', 'name': 'file3.txt', 'size_mb': 3.0}
          },
          timestamp: DateTime.now().add(const Duration(milliseconds: 20)),
        ),
      );

      expect(pendingBox.length, equals(3));

      await syncQueue.processQueue();

      // All 3 contiguous items should be batched together in 1 call
      expect(mockMeta.addBatchCalls, equals(1));
      expect(mockMeta.lastBatchList.length, equals(3));
      expect(pendingBox.length, equals(0));

      // Consolidated batch log should exist and be completed
      final completedBatchLog = syncQueue.logsNotifier.value
          .firstWhere((l) => l.description.contains('3 files'));
      expect(completedBatchLog.status, equals('completed'));
    });

    test('TC-03: processQueue(force: true) resets backoff and executes immediately',
        () async {
      await pendingBox.put(
        'add-force',
        PendingAction(
          id: 'add-force',
          actionType: AppConstants.actionAddFileMeta,
          payload: {
            'fileMeta': {'file_id': 'f_force', 'name': 'f.txt', 'size_mb': 0.5}
          },
          timestamp: DateTime.now(),
        ),
      );

      // Force process queue
      await syncQueue.processQueue(force: true);

      expect(pendingBox.length, equals(0));
      expect(mockMeta.addBatchCalls, equals(1)); // Processed via unified batch API
    });
  });
}
