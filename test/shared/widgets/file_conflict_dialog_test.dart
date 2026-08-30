/*
 * File: file_conflict_dialog_test.dart
 * Description: Widget and interaction tests for file conflict dialog, batch checkbox behavior, and BrowserBatchHelper lazy evaluation loop.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/download_job.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/download_queue_service.dart';
import 'package:telstorage/core/services/download_service.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_batch_helper.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_state.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';
import 'package:telstorage/shared/widgets/dialogs/app_dialogs.dart';

class _MockStorageRepo implements StorageRepositoryContract {
  final List<FileRecord> files;
  final List<FolderRecord> folders;

  _MockStorageRepo({required this.files, required this.folders});

  @override
  List<FileRecord> get currentFiles => files;

  @override
  List<FolderRecord> get currentFolders => folders;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('File Conflict Dialog UI', () {
    testWidgets('Single-file mode: Cancel button returns skip policy', (tester) async {
      FileConflictDecision? result;

      await tester.pumpWidget(wrapWithTheme(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await AppDialogs.showFileConflictDialog(
                context,
                fileName: 'photo.jpg',
                isBatch: false,
              );
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('File Already Exists'), findsOneWidget);
      expect(find.text('"photo.jpg" is already saved on your device.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Keep Both'), findsOneWidget);
      expect(find.text('Overwrite'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.policy, DownloadConflictPolicy.skip);
      expect(result!.applyToAll, isFalse);
    });

    testWidgets('Single-file mode: Overwrite returns overwrite policy', (tester) async {
      FileConflictDecision? result;

      await tester.pumpWidget(wrapWithTheme(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await AppDialogs.showFileConflictDialog(
                context,
                fileName: 'doc.pdf',
                isBatch: false,
              );
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Overwrite'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.policy, DownloadConflictPolicy.overwrite);
      expect(result!.applyToAll, isFalse);
    });

    testWidgets('Single-file mode: Keep Both returns keepBoth policy', (tester) async {
      FileConflictDecision? result;

      await tester.pumpWidget(wrapWithTheme(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await AppDialogs.showFileConflictDialog(
                context,
                fileName: 'track.mp3',
                isBatch: false,
              );
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keep Both'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.policy, DownloadConflictPolicy.keepBoth);
      expect(result!.applyToAll, isFalse);
    });

    testWidgets('Batch mode: shows Checkbox and returns applyToAll = true when checked', (tester) async {
      FileConflictDecision? result;

      await tester.pumpWidget(wrapWithTheme(
        Builder(builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              result = await AppDialogs.showFileConflictDialog(
                context,
                fileName: 'batch_file.png',
                isBatch: true,
              );
            },
            child: const Text('Open'),
          );
        }),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Skip'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
      expect(find.text('Apply to remaining conflicts'), findsOneWidget);

      // Toggle Checkbox
      await tester.tap(find.text('Apply to remaining conflicts'));
      await tester.pumpAndSettle();

      // Click Overwrite
      await tester.tap(find.text('Overwrite'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.policy, DownloadConflictPolicy.overwrite);
      expect(result!.applyToAll, isTrue);
    });
  });

  group('BrowserBatchHelper Conflict Loop Evaluation', () {
    late Directory tempDir;
    late Box<DownloadJob> downloadsBox;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('batch_conflict_test_');
      Hive.init(tempDir.path);
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(FileRecordAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(FolderRecordAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(DownloadJobAdapter());
      }
    });

    setUp(() async {
      await Hive.openBox<FileRecord>(AppConstants.filesBox);
      await Hive.openBox<FolderRecord>(AppConstants.foldersBox);
      downloadsBox = await Hive.openBox<DownloadJob>(AppConstants.downloadsBox);
      await downloadsBox.clear();
      final downloadService = DownloadService(TelegramService());
      ServiceLocator.instance.setDownloadServiceForTesting(downloadService);
      ServiceLocator.instance.setHiveForTesting(HiveService.instance);
      ServiceLocator.instance.setInitializedForTesting(true);
      ServiceLocator.instance.setDownloadQueueForTesting(
        DownloadQueueService(downloadService, AppConstants.downloadsBox),
      );
    });

    tearDown(() async {
      await downloadsBox.clear();
      await downloadsBox.close();
      await Hive.box<FileRecord>(AppConstants.filesBox).clear();
      await Hive.box<FileRecord>(AppConstants.filesBox).close();
      await Hive.box<FolderRecord>(AppConstants.foldersBox).clear();
      await Hive.box<FolderRecord>(AppConstants.foldersBox).close();
      ServiceLocator.instance.setInitializedForTesting(false);
    });

    tearDownAll(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Batch download loop respects Apply-To-All decision across all remaining items', () async {
      final f1 = FileRecord(fileId: 'b_f1', name: 'f1.txt', mimeType: 'text/plain', sizeMb: 1.0, uploadedAt: DateTime.now(), metadataMessageId: 201, chunkCount: 1, sha256Hash: 'h1');
      final f2 = FileRecord(fileId: 'b_f2', name: 'f2.txt', mimeType: 'text/plain', sizeMb: 1.0, uploadedAt: DateTime.now(), metadataMessageId: 202, chunkCount: 1, sha256Hash: 'h2');

      // Mark f1 and f2 as completed to trigger conflict
      await downloadsBox.put(f1.fileId, DownloadJob(fileId: f1.fileId, name: f1.name, mimeType: f1.mimeType, sizeMb: 1.0, status: 'completed', progress: 1.0, addedAt: DateTime.now()));
      await downloadsBox.put(f2.fileId, DownloadJob(fileId: f2.fileId, name: f2.name, mimeType: f2.mimeType, sizeMb: 1.0, status: 'completed', progress: 1.0, addedAt: DateTime.now()));

      final repo = _MockStorageRepo(files: [f1, f2], folders: []);
      final state = BrowserState(selectedFileIds: {f1.fileId, f2.fileId});

      var promptCount = 0;
      final enqueued = await BrowserBatchHelper.executeBatchDownload(
        state: state,
        repository: repo,
        conflictResolver: (name) async {
          promptCount++;
          return const FileConflictDecision(policy: DownloadConflictPolicy.keepBoth, applyToAll: true);
        },
      );

      expect(enqueued, 2);
      expect(promptCount, 1); // Prompted only once because applyToAll was cached
      expect(ServiceLocator.instance.downloadQueue.getConflictPolicy(f1.fileId), DownloadConflictPolicy.keepBoth);
      expect(ServiceLocator.instance.downloadQueue.getConflictPolicy(f2.fileId), DownloadConflictPolicy.keepBoth);
    });

    test('Batch download loop aborts when user dismisses dialog (returns null)', () async {
      final f1 = FileRecord(fileId: 'c_f1', name: 'c1.txt', mimeType: 'text/plain', sizeMb: 1.0, uploadedAt: DateTime.now(), metadataMessageId: 301, chunkCount: 1, sha256Hash: 'h1');
      final f2 = FileRecord(fileId: 'c_f2', name: 'c2.txt', mimeType: 'text/plain', sizeMb: 1.0, uploadedAt: DateTime.now(), metadataMessageId: 302, chunkCount: 1, sha256Hash: 'h2');

      await downloadsBox.put(f1.fileId, DownloadJob(fileId: f1.fileId, name: f1.name, mimeType: f1.mimeType, sizeMb: 1.0, status: 'completed', progress: 1.0, addedAt: DateTime.now()));
      await downloadsBox.put(f2.fileId, DownloadJob(fileId: f2.fileId, name: f2.name, mimeType: f2.mimeType, sizeMb: 1.0, status: 'completed', progress: 1.0, addedAt: DateTime.now()));

      final repo = _MockStorageRepo(files: [f1, f2], folders: []);
      final state = BrowserState(selectedFileIds: {f1.fileId, f2.fileId});

      var promptCount = 0;
      final enqueued = await BrowserBatchHelper.executeBatchDownload(
        state: state,
        repository: repo,
        conflictResolver: (name) async {
          promptCount++;
          return null; // User cancelled batch
        },
      );

      expect(enqueued, 0);
      expect(promptCount, 1);
    });
  });
}
