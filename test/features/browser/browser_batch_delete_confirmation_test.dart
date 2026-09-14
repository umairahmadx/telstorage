/*
 * File: browser_batch_delete_confirmation_test.dart
 * Description: Automated reproduction test verifying that tapping delete in multi-selection mode displays a confirmation dialog before executing deletion.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/browser_screen.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'package:telstorage/features/storage/data/repositories/storage_repository.dart';

class _FakeBatchDeleteStorageRepo implements StorageRepository {
  final List<String> deletedFileIds = [];
  final List<String> deletedFolderIds = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  List<FileRecord> get currentFiles => [
        FileRecord(
          fileId: 'f-1',
          name: 'photo.jpg',
          sizeMb: 1.0,
          metadataMessageId: 1,
          mimeType: 'image/jpeg',
          uploadedAt: DateTime.now(),
          chunkCount: 1,
          sha256Hash: 'hash1',
        ),
        FileRecord(
          fileId: 'f-2',
          name: 'document.pdf',
          sizeMb: 2.0,
          metadataMessageId: 2,
          mimeType: 'application/pdf',
          uploadedAt: DateTime.now(),
          chunkCount: 1,
          sha256Hash: 'hash2',
        ),
      ];

  @override
  List<FolderRecord> get currentFolders => [];

  @override
  List<FolderRecord> getFolders(String? parentId) => [];

  @override
  List<FileRecord> getFiles(String? folderId) => currentFiles;

  @override
  Future<Result<void>> deleteFile(String fileId) async {
    deletedFileIds.add(fileId);
    return const Success(null);
  }

  @override
  Future<Result<void>> deleteFolder(String folderId) async {
    deletedFolderIds.add(folderId);
    return const Success(null);
  }
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Browser Batch Delete Confirmation Tests', () {
    testWidgets(
        'Tapping delete in multi-select mode displays confirmation dialog before deleting',
        (tester) async {
      final fakeRepo = _FakeBatchDeleteStorageRepo();
      ServiceLocator.instance.setStorageRepositoryForTesting(fakeRepo);

      final bloc = BrowserBloc(fakeRepo);
      bloc.add(ToggleItemSelection('f-1', isFolder: false));
      bloc.add(ToggleItemSelection('f-2', isFolder: false));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: BlocProvider<BrowserBloc>.value(
            value: bloc,
            child: const BrowserScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
      final deleteBtn = find.byIcon(Icons.delete_outline_rounded);
      expect(deleteBtn, findsOneWidget);

      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Delete 2 files?'), findsOneWidget);
      expect(fakeRepo.deletedFileIds, isEmpty);
    });

    testWidgets(
        'Cancelling confirmation dialog dismisses without deleting or clearing selection',
        (tester) async {
      final fakeRepo = _FakeBatchDeleteStorageRepo();
      ServiceLocator.instance.setStorageRepositoryForTesting(fakeRepo);

      final bloc = BrowserBloc(fakeRepo);
      bloc.add(ToggleItemSelection('f-1', isFolder: false));
      bloc.add(ToggleItemSelection('f-2', isFolder: false));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: BlocProvider<BrowserBloc>.value(
            value: bloc,
            child: const BrowserScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      // Tap Cancel button
      final cancelBtn = find.widgetWithText(TextButton, 'Cancel');
      expect(cancelBtn, findsOneWidget);
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();

      // Dialog is dismissed, no deletion performed, items still selected
      expect(find.byType(AlertDialog), findsNothing);
      expect(fakeRepo.deletedFileIds, isEmpty);
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets(
        'Confirming dialog dispatches batch deletion and deletes all selected items',
        (tester) async {
      final fakeRepo = _FakeBatchDeleteStorageRepo();
      ServiceLocator.instance.setStorageRepositoryForTesting(fakeRepo);

      final bloc = BrowserBloc(fakeRepo);
      bloc.add(ToggleItemSelection('f-1', isFolder: false));
      bloc.add(ToggleItemSelection('f-2', isFolder: false));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: BlocProvider<BrowserBloc>.value(
            value: bloc,
            child: const BrowserScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();

      // Tap Delete (destructive FilledButton in dialog)
      final confirmDeleteBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Delete'),
      );
      expect(confirmDeleteBtn, findsOneWidget);
      await tester.tap(confirmDeleteBtn);
      await tester.pumpAndSettle();

      // Deletion executed through repository
      expect(fakeRepo.deletedFileIds, containsAll(['f-1', 'f-2']));
    });
  });
}
