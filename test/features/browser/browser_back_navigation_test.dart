/*
 * File: browser_back_navigation_test.dart
 * Description: Widget tests verifying PopScope back gesture interception and NavigateUp behavior in BrowserScreen.
 */

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/folder_stats.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/browser_screen.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';

class _FakeStorageRepository implements StorageRepositoryContract {
  @override
  List<FileRecord> get currentFiles => [];

  @override
  List<FolderRecord> get currentFolders => [];

  @override
  FileRecord? getFile(String fileId) => null;

  @override
  FolderRecord? getFolder(String folderId) {
    if (folderId == 'child-folder') {
      return FolderRecord(
        id: 'child-folder',
        name: 'Child Folder',
        parentId: null, // parent is root
        createdAt: DateTime.now(),
      );
    }
    return null;
  }

  @override
  List<FolderRecord> getFolders(String? parentId) => [];

  @override
  List<FileRecord> getFiles(String? folderId) => [];

  @override
  int getFilesInFolderCount(String folderId) => 0;

  @override
  FolderStats getFolderStats(String folderId) => const FolderStats(
        fileCount: 0,
        subfolderCount: 0,
        totalSizeMb: 0.0,
      );

  @override
  Future<Result<String>> createFolder(String name, {String? parentId}) async =>
      const Success('created-1');

  @override
  Future<Result<void>> renameFolder(String folderId, String newName) async =>
      const Success(null);

  @override
  Future<Result<void>> deleteFolder(String folderId) async =>
      const Success(null);

  @override
  Future<void> moveFolder(String folderId, String? newParentId) async {}

  @override
  Future<void> copyFolder(String folderId, String? targetParentId) async {}

  @override
  Future<Result<void>> renameFile(String fileId, String newName) async =>
      const Success(null);

  @override
  Future<void> moveFile(String fileId, String? newFolderId) async {}

  @override
  Future<Result<void>> copyFile(String fileId, String? targetFolderId) async =>
      const Success(null);

  @override
  Future<Result<void>> deleteFile(String fileId) async =>
      const Success(null);

  @override
  Future<Result<void>> enqueueDownload(FileRecord file) async =>
      const Success(null);

  @override
  Future<Result<void>> enqueueWebShare(
    FileRecord file, {
    String? password,
    int? expiryDays,
    String? vanitySlug,
  }) async =>
      const Success(null);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('BrowserScreen wraps in PopScope to handle OS back gestures inside folders', (tester) async {
    final fakeRepo = _FakeStorageRepository();
    final bloc = BrowserBloc(fakeRepo);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: BlocProvider<BrowserBloc>.value(
          value: bloc,
          child: const BrowserScreen(),
        ),
      ),
    );

    // Initial root state -> PopScope exists
    final popScopeFinder = find.byWidgetPredicate((widget) => widget is PopScope);
    expect(popScopeFinder, findsOneWidget);
    var popScopeWidget = tester.widget<PopScope>(popScopeFinder);
    expect(popScopeWidget.canPop, isTrue);

    // Enter child folder
    bloc.emit(bloc.state.copyWith(currentFolderId: 'child-folder'));
    await tester.pump(const Duration(milliseconds: 100));

    popScopeWidget = tester.widget<PopScope>(popScopeFinder);
    // When inside child folder, canPop must be false so OS back is intercepted
    expect(popScopeWidget.canPop, isFalse);
  });
}
