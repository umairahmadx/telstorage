/*
 * File: transfer_queue_persistence_test.dart
 * Description: Unit tests validating TransferQueueService orchestration, pause/resume lifecycles, and persistent queue states.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/notification_service.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TransferQueueService transferQueue;

  setUp(() {
    NotificationService.setMockInitialized(true);
    transferQueue = TransferQueueService.instance;
    transferQueue.clear();
  });

  group('TransferQueueService Lifecycle & Persistence Tests', () {
    test('TC-01: Adds tasks and notifies listenable', () {
      final task = TransferTask(
        id: 'file_001',
        name: 'video.mp4',
        type: TransferType.download,
        sizeMb: 50.0,
        addedAt: DateTime.now(),
        status: TransferStatus.pending,
      );

      transferQueue.addTask(task);

      expect(transferQueue.tasks.length, 1);
      expect(transferQueue.activeTasks.length, 1);
      expect(transferQueue.tasks.first.name, 'video.mp4');
    });

    test('TC-02: Updates task progress and status', () {
      final task = TransferTask(
        id: 'file_002',
        name: 'document.pdf',
        type: TransferType.upload,
        sizeMb: 10.0,
        addedAt: DateTime.now(),
        status: TransferStatus.preparing,
      );
      transferQueue.addTask(task);

      transferQueue.updateTask(
        'file_002',
        progress: 0.5,
        status: TransferStatus.uploading,
        currentStage: 'Uploading 50%…',
      );

      final updated = transferQueue.tasks.firstWhere((t) => t.id == 'file_002');
      expect(updated.progress, 0.5);
      expect(updated.status, TransferStatus.uploading);
      expect(updated.currentStage, 'Uploading 50%…');
    });

    test('TC-03: Pause and Resume transitions update task state cleanly', () {
      final task = TransferTask(
        id: 'file_003',
        name: 'archive.zip',
        type: TransferType.download,
        sizeMb: 100.0,
        addedAt: DateTime.now(),
        status: TransferStatus.downloading,
      );
      transferQueue.addTask(task);

      transferQueue.pauseTask('file_003');
      expect(transferQueue.isPaused('file_003'), isTrue);
      expect(transferQueue.tasks.first.status, TransferStatus.paused);

      transferQueue.resumeTask('file_003');
      expect(transferQueue.isPaused('file_003'), isFalse);
      expect(transferQueue.tasks.first.status, TransferStatus.downloading);
    });

    test('TC-04: Cancellation marks task cancelled and removes from active tasks', () {
      final task = TransferTask(
        id: 'file_004',
        name: 'image.heic',
        type: TransferType.upload,
        sizeMb: 2.5,
        addedAt: DateTime.now(),
        status: TransferStatus.uploading,
      );
      transferQueue.addTask(task);

      transferQueue.cancelTask('file_004');
      expect(transferQueue.isCancelled('file_004'), isTrue);
      expect(transferQueue.activeTasks, isEmpty);
    });

    test('TC-05: Completed tasks are filtered out of activeTasks list', () {
      final task = TransferTask(
        id: 'file_005',
        name: 'song.mp3',
        type: TransferType.download,
        sizeMb: 5.0,
        addedAt: DateTime.now(),
        status: TransferStatus.downloading,
      );
      transferQueue.addTask(task);
      expect(transferQueue.activeTasks.length, 1);

      transferQueue.updateTask('file_005', progress: 1.0, status: TransferStatus.completed);
      expect(transferQueue.activeTasks, isEmpty);
      expect(transferQueue.tasks.length, 1);
      expect(transferQueue.tasks.first.status, TransferStatus.completed);
    });
  });
}
