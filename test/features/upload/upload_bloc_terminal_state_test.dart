/*
 * File: upload_bloc_terminal_state_test.dart
 * Description: Automated reproduction test verifying UploadBloc fails to mark
 * tasks as failed in TransferQueueService when files are inaccessible or fail.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/notification_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';
import 'package:telstorage/core/services/upload_service.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_view_model.dart';

class _FakeUploadService implements UploadService {
  _FakeUploadService();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeUploadService fakeUploadService;
  late UploadBloc bloc;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('upload_bloc_repro_');
    fakeUploadService = _FakeUploadService();
    ServiceLocator.instance.setUploadServiceForTesting(fakeUploadService);
    ServiceLocator.instance.setInitializedForTesting(true);
    NotificationService.setMockInitialized(true);
    Connectivity.mockConnectionStatus = true;
    TransferQueueService.instance.clearAll();
    bloc = UploadBloc();
  });

  tearDown(() async {
    await bloc.close();
    Connectivity.mockConnectionStatus = null;
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('UploadBloc Terminal State Reproduction', () {
    test('inaccessible file must update TransferQueueService status to failed',
        () async {
      final task = UploadTask(
        id: 'backup_repro_task_1',
        path: '${tempDir.path}/non_existent_file.jpg',
        name: 'non_existent_file.jpg',
        size: 2048,
      );

      // Add task to bloc
      bloc.add(AddUploads([task]));

      // Allow the bloc to process ProcessNextUpload and checkFileExists
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Assert that TransferQueueService task is updated to TransferStatus.failed
      final queued = TransferQueueService.instance.tasks
          .firstWhere((t) => t.id == task.id);

      // In current un-fixed code, this assertion FAILS because the status
      // remains TransferStatus.waiting!
      expect(
        queued.status,
        TransferStatus.failed,
        reason:
            'Task in TransferQueueService must transition to TransferStatus.failed when file is inaccessible',
      );
    });
  });
}
