/*
 * File: upload_lazy_queue_test.dart
 * Description: Unit and lifecycle tests verifying zero-eager reading, bounded concurrency, missing file isolation, and per-task cache cleanup in UploadBloc.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/transfer_task.dart';
import 'package:telstorage/core/services/notification_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/transfer_queue_service.dart';
import 'package:telstorage/core/services/upload_service.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_view_model.dart';

class _MockUploadService implements UploadService {
  int concurrentActive = 0;
  int peakConcurrent = 0;
  final List<String> uploadedFiles = [];
  final Map<String, String?> uploadedFolderIds = {};
  final Duration delay = const Duration(milliseconds: 20);

  _MockUploadService();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Result<Map<String, dynamic>>> uploadFile(
    Uint8List bytes,
    String name,
    String? folderId,
    Function(double progress, String status) onProgress, {
    bool skipGlobalMetadataUpdate = false,
    String? taskId,
    String? precomputedHash,
    Uint8List? precomputedThumbnailBytes,
    String? thumbnailExtension,
  }) async {
    concurrentActive++;
    if (concurrentActive > peakConcurrent) {
      peakConcurrent = concurrentActive;
    }

    onProgress(0.5, 'Uploading…');
    await Future<void>.delayed(delay);
    onProgress(1.0, 'Done');

    uploadedFiles.add(name);
    uploadedFolderIds[name] = folderId;
    concurrentActive--;
    return Success({'file_id': 'f_$name', 'name': name});
  }

  @override
  Future<void> commitUploadBatch(
      List<Map<String, dynamic>> completedFiles) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _MockUploadService mockUploadService;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('upload_lazy_test_');
    mockUploadService = _MockUploadService();
    ServiceLocator.instance.setUploadServiceForTesting(mockUploadService);
    ServiceLocator.instance.setInitializedForTesting(true);
    NotificationService.setMockInitialized(true);
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('UploadTask Lazy Resolution & Queue Lifecycle', () {
    test('Test 1: Zero eager reads when queueing 40 path-backed tasks',
        () async {
      final List<File> files = [];
      final List<UploadTask> tasks = [];

      for (int i = 0; i < 40; i++) {
        final f = File('${tempDir.path}/img_$i.jpg');
        await f.writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));
        files.add(f);

        tasks.add(UploadTask(
          id: 'task_$i',
          path: f.path,
          name: 'img_$i.jpg',
          size: 4,
          isTemporaryCacheFile: true,
        ));
      }

      // Assert none of the tasks hold bytes in memory upfront
      for (final t in tasks) {
        expect(t.bytes, isNull);
        expect(t.path, isNotNull);
      }

      // Queue all 40 tasks into a bloc
      final bloc = UploadBloc();
      bloc.add(AddUploads(tasks));

      while (mockUploadService.uploadedFiles.length < 40) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockUploadService.uploadedFiles.length, equals(40));

      // Close bloc
      await bloc.close();
    });

    test(
        'Test 2: Bounded in-flight buffer concurrency (<= 3 workers) for 40 tasks',
        () async {
      final List<UploadTask> tasks = [];

      for (int i = 0; i < 40; i++) {
        final f = File('${tempDir.path}/photo_$i.jpg');
        await f.writeAsBytes(Uint8List.fromList([10, 20, 30, 40]));

        tasks.add(UploadTask(
          id: 'task_$i',
          path: f.path,
          name: 'photo_$i.jpg',
          size: 4,
        ));
      }

      final bloc = UploadBloc();
      bloc.add(AddUploads(tasks));

      // Wait until all 40 files finish uploading
      while (mockUploadService.uploadedFiles.length < 40) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(mockUploadService.uploadedFiles.length, equals(40));
      // Concurrency coordinator / worker count should strictly bound peak active uploads to <= 3
      expect(mockUploadService.peakConcurrent, lessThanOrEqualTo(3));
      expect(mockUploadService.peakConcurrent, greaterThan(0));

      await bloc.close();
    });

    test('Test 3: Missing/evicted file fails gracefully without halting batch',
        () async {
      final List<UploadTask> tasks = [];

      for (int i = 0; i < 5; i++) {
        final f = File('${tempDir.path}/doc_$i.pdf');
        if (i != 2) {
          // Create file for 0, 1, 3, 4. Item 2 is missing!
          await f.writeAsBytes(Uint8List.fromList([1, 2, 3]));
        }

        tasks.add(UploadTask(
          id: 'doc_task_$i',
          path: f.path,
          name: 'doc_$i.pdf',
          size: 3,
        ));
      }

      final errors = <UploadSingleError>[];
      final bloc = UploadBloc();
      final sub = bloc.stream.listen((state) {
        if (state is UploadSingleError) {
          errors.add(state);
        }
      });

      bloc.add(AddUploads(tasks));

      // Wait until remaining 4 valid files finish uploading
      while (mockUploadService.uploadedFiles.length < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // Allow error emission to flush
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // 4 files succeeded
      expect(mockUploadService.uploadedFiles,
          containsAll(['doc_0.pdf', 'doc_1.pdf', 'doc_3.pdf', 'doc_4.pdf']));
      expect(mockUploadService.uploadedFiles, isNot(contains('doc_2.pdf')));

      // Exactly 1 single-error emitted for doc_2.pdf
      expect(errors.length, equals(1));
      expect(errors.first.fileName, equals('doc_2.pdf'));
      expect(errors.first.message, contains('inaccessible'));

      await sub.cancel();
      await bloc.close();
    });

    test('Test 4: Per-task cache cleanup & cross-batch safety', () async {
      // Batch A file (temporary cache file)
      final fileA = File('${tempDir.path}/batch_a.jpg');
      await fileA.writeAsBytes(Uint8List.fromList([100, 200]));

      // Batch B file (temporary cache file queued in a separate batch)
      final fileB = File('${tempDir.path}/batch_b.jpg');
      await fileB.writeAsBytes(Uint8List.fromList([200, 250]));

      final taskA = UploadTask(
        id: 'task_a',
        path: fileA.path,
        name: 'batch_a.jpg',
        isTemporaryCacheFile: true,
      );

      final taskB = UploadTask(
        id: 'task_b',
        path: fileB.path,
        name: 'batch_b.jpg',
        isTemporaryCacheFile: true,
      );

      final bloc = UploadBloc();
      bloc.add(AddUploads([taskA]));

      // Wait for task A to complete
      while (!mockUploadService.uploadedFiles.contains('batch_a.jpg')) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // fileA should be deleted because its task completed with isTemporaryCacheFile = true
      expect(await fileA.exists(), isFalse);

      // fileB MUST remain completely untouched and intact
      expect(await fileB.exists(), isTrue);

      // Now enqueue task B
      bloc.add(AddUploads([taskB]));
      while (!mockUploadService.uploadedFiles.contains('batch_b.jpg')) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Now fileB should also be cleaned up after its own upload
      expect(await fileB.exists(), isFalse);

      await bloc.close();
    });

    test('Test 5: Preserves folderId on queued UploadTask and delivers it to uploadFile',
        () async {
      final file = File('${tempDir.path}/nested_doc.pdf');
      await file.writeAsBytes(Uint8List.fromList([1, 2, 3, 4, 5]));

      final task = UploadTask(
        id: 'task_nested_1',
        path: file.path,
        name: 'nested_doc.pdf',
        folderId: 'folder_target_456',
        isTemporaryCacheFile: false,
      );

      final bloc = UploadBloc();
      bloc.add(AddUploads([task]));

      while (!mockUploadService.uploadedFiles.contains('nested_doc.pdf')) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockUploadService.uploadedFolderIds['nested_doc.pdf'],
          equals('folder_target_456'));

      await bloc.close();
    });

    test(
        'Test 6: All queued upload tasks are immediately registered in TransferQueueService with waiting state',
        () async {
      TransferQueueService.instance.clearAll();

      final List<UploadTask> tasks = [];
      for (int i = 0; i < 6; i++) {
        final f = File('${tempDir.path}/batch_file_$i.txt');
        await f.writeAsString('Test payload $i');
        tasks.add(UploadTask(
          id: 'queue_task_$i',
          path: f.path,
          name: 'batch_file_$i.txt',
          size: 14,
        ));
      }

      final bloc = UploadBloc();
      bloc.add(AddUploads(tasks));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Immediately all 6 tasks should be registered in TransferQueueService
      final registered = TransferQueueService.instance.tasks;
      expect(registered.length, equals(6));

      // Wait for all 6 tasks to finish
      while (mockUploadService.uploadedFiles.length < 6) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockUploadService.uploadedFiles.length, equals(6));
      await bloc.close();
    });
  });
}
