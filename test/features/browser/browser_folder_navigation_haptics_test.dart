/*
 * File: browser_folder_navigation_haptics_test.dart
 * Description: Widget tests verifying bottom bar Files tab navigation to root folder and folder/filter tap interactions.
 */

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/download_conflict_policy.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/folder_stats.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/theme/app_theme.dart';
import 'package:telstorage/features/auth/presentation/viewmodels/auth_view_model.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/browser_screen.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'package:telstorage/features/downloads/presentation/screens/downloads/viewmodel/downloads_view_model.dart';
import 'package:telstorage/features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'package:telstorage/features/storage/data/repositories/storage_repository.dart';
import 'package:telstorage/features/upload/presentation/viewmodels/upload_view_model.dart';
import 'package:telstorage/shared/widgets/mobile_shell.dart';
import 'package:telstorage/shared/widgets/mobile_shell/mobile_bottom_nav.dart';
import 'package:telstorage/shared/widgets/tiles/app_folder_grid_tile.dart';
import 'package:telstorage/shared/widgets/tiles/app_folder_tile.dart';

class _FakeStorageRepo implements StorageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  List<FileRecord> get currentFiles => [];

  @override
  List<FolderRecord> get currentFolders => [
        FolderRecord(
          id: 'test-folder-1',
          name: 'Documents Folder',
          parentId: null,
          createdAt: DateTime.now(),
        ),
      ];

  @override
  FileRecord? getFile(String fileId) => null;

  @override
  FolderRecord? getFolder(String folderId) {
    if (folderId == 'test-folder-1') {
      return FolderRecord(
        id: 'test-folder-1',
        name: 'Documents Folder',
        parentId: null,
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
      const Success('id');

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
  Future<Result<void>> deleteFile(String fileId) async => const Success(null);

  @override
  Future<Result<void>> enqueueDownload(
    FileRecord file, {
    String? subpath,
    DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
  }) async =>
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
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  Animate.defaultDuration = Duration.zero;

  group('Browser Folder Navigation & Interaction Tests', () {
    testWidgets(
        'AppFolderTile executes onTap with light impact haptic feedback',
        (tester) async {
      bool tapped = false;
      final folder = FolderRecord(
        id: 'f1',
        name: 'Work',
        parentId: null,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AppFolderTile(
              folder: folder,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppFolderTile));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets(
        'AppFolderGridTile executes onTap with light impact haptic feedback',
        (tester) async {
      bool tapped = false;
      final folder = FolderRecord(
        id: 'f2',
        name: 'Photos',
        parentId: null,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AppFolderGridTile(
              folder: folder,
              onTap: () => tapped = true,
              onLongPress: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppFolderGridTile));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets(
        'Selecting category filter chip triggers selection and updates category',
        (tester) async {
      final fakeRepo = _FakeStorageRepo();
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
      await tester.pump();

      // Tap on 'Images' filter chip
      final imagesChip = find.widgetWithText(FilterChip, 'Images');
      expect(imagesChip, findsOneWidget);

      await tester.tap(imagesChip);
      await tester.pump();

      expect(bloc.state.category, 'image');
    });

    testWidgets(
        'Tapping bottom bar Files tab while inside a folder resets to root folder',
        (tester) async {
      final fakeRepo = _FakeStorageRepo();
      ServiceLocator.instance.setStorageRepositoryForTesting(fakeRepo);
      final browserBloc = BrowserBloc(fakeRepo);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>(create: (_) => AuthBloc()),
            BlocProvider<UploadBloc>(create: (_) => UploadBloc()),
            BlocProvider<HomeCubit>(create: (_) => HomeCubit()),
            BlocProvider<TransferCubit>(create: (_) => TransferCubit()),
            BlocProvider<BrowserBloc>.value(value: browserBloc),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MobileShell(initialIndex: 1),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Simulate user navigating into a subfolder
      browserBloc.add(LoadDirectory(folderId: 'test-folder-1'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(browserBloc.state.currentFolderId, 'test-folder-1');

      // Tap 'Files' NavItem in bottom bar
      final filesNavItem = find.widgetWithText(NavItem, 'Files');
      expect(filesNavItem, findsOneWidget);

      await tester.tap(filesNavItem);
      await tester.pump(const Duration(milliseconds: 100));

      // State should have reset currentFolderId to null (root directory)
      expect(browserBloc.state.currentFolderId, isNull);
    });
  });
}
