/*
 * File: codebase_improvements_audit_test.dart
 * Description: Tests verifying the resilience and edge-case improvements across BrowserBloc, MetadataService, and FileManagerService.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';

class _FakeTelegramService implements TelegramService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMetadataService implements MetadataService {
  final AppMetadata _meta;
  _FakeMetadataService(this._meta);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<AppMetadata> fetch() async => _meta;
}

class _FakeHiveService implements HiveService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBrowserStorageRepo implements StorageRepositoryContract {
  final List<FolderRecord> _folders;
  final List<FileRecord> _files;

  _FakeBrowserStorageRepo(this._folders, this._files);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  List<FolderRecord> getFolders(String? parentId) =>
      _folders.where((f) => f.parentId == parentId).toList();

  @override
  List<FileRecord> getFiles(String? folderId) =>
      _files.where((f) => f.folderId == folderId).toList();

  @override
  FolderRecord? getFolder(String folderId) =>
      _folders.where((f) => f.id == folderId).firstOrNull;

  @override
  int getFilesInFolderCount(String folderId) =>
      _files.where((f) => f.folderId == folderId).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Codebase Improvements Audit Tests', () {
    test('TC-01: BrowserBloc resets searchQuery when navigating to a different folder', () async {
      final repo = _FakeBrowserStorageRepo([
        FolderRecord(id: 'f1', name: 'Work', parentId: null, createdAt: DateTime.now(), itemCount: 1),
      ], [
        FileRecord(
          fileId: 'file-1',
          name: 'notes.txt',
          folderId: 'f1',
          metadataMessageId: 1,
          metadataFileId: 'mf1',
          sizeMb: 0.1,
          mimeType: 'text/plain',
          uploadedAt: DateTime.now(),
          chunkCount: 1,
          sha256Hash: 'hash',
        ),
      ]);

      final bloc = BrowserBloc(repo);

      // User sets search query at root
      bloc.add(SearchQueryChanged('query_at_root'));
      await pumpEventQueue();
      expect(bloc.state.searchQuery, 'query_at_root');

      // User clicks into folder f1
      bloc.add(LoadDirectory(folderId: 'f1'));
      await pumpEventQueue();

      // Search query should be automatically reset to empty string
      expect(bloc.state.searchQuery, '');
      expect(bloc.state.currentFolderId, 'f1');
      expect(bloc.state.files.length, 1);
      expect(bloc.state.files.first.name, 'notes.txt');

      await bloc.close();
    });

    test('TC-02: FileManagerService throws descriptive exception if folder is missing during rename or move', () async {
      final emptyMeta = AppMetadata(
        owner: 'test@example.com',
        storageUsedMb: 0,
        totalFiles: 0,
        metadataMessageId: 1,
        folders: [],
        categories: {},
        lastSynced: DateTime.now(),
      );

      final fakeMeta = _FakeMetadataService(emptyMeta);
      final fakeTg = _FakeTelegramService();
      final fakeHive = _FakeHiveService();

      final manager = FileManagerService(fakeMeta, fakeTg, fakeHive);

      expect(
        () => manager.renameFolder('non_existent_folder', 'New Name'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Folder "non_existent_folder" not found in remote metadata'),
        )),
      );

      expect(
        () => manager.moveFolder('non_existent_folder', 'target_parent'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Folder "non_existent_folder" not found in remote metadata'),
        )),
      );
    });
  });
}
