/*
 * File: folder_navigation_partition_fix_test.dart
 * Description: Unit tests verifying immediate local folder loading, LocalContentsChanged decoupling, and folder itemCount persistence.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';

class _FakeNavigationStorageRepo implements StorageRepositoryContract {
  final List<FolderRecord> _folders;
  final List<FileRecord> _files;

  _FakeNavigationStorageRepo(this._folders, this._files);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  List<FolderRecord> getFolders(String? parentId) {
    return _folders.where((f) => f.parentId == parentId).toList();
  }

  @override
  List<FileRecord> getFiles(String? folderId) {
    return _files.where((f) => f.folderId == folderId).toList();
  }

  @override
  FolderRecord? getFolder(String folderId) {
    try {
      return _folders.firstWhere((f) => f.id == folderId);
    } catch (_) {
      return null;
    }
  }

  @override
  int getFilesInFolderCount(String folderId) {
    return _files.where((f) => f.folderId == folderId).length;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Folder Navigation & Partition Fix Tests', () {
    late _FakeNavigationStorageRepo repo;
    late List<FolderRecord> folders;
    late List<FileRecord> files;

    setUp(() {
      folders = [
        FolderRecord(
          id: 'folder-root-1',
          name: 'Documents',
          parentId: null,
          createdAt: DateTime(2026, 1, 1),
          itemCount: 2,
        ),
        FolderRecord(
          id: 'subfolder-1',
          name: 'Projects',
          parentId: 'folder-root-1',
          createdAt: DateTime(2026, 1, 2),
          itemCount: 0,
        ),
      ];

      files = [
        FileRecord(
          fileId: 'root-file-1',
          name: 'root_note.txt',
          folderId: null,
          metadataMessageId: 101,
          sizeMb: 1.0,
          mimeType: 'text/plain',
          uploadedAt: DateTime(2026, 1, 1),
          chunkCount: 1,
          sha256Hash: '',
        ),
        FileRecord(
          fileId: 'doc-file-1',
          name: 'report.pdf',
          folderId: 'folder-root-1',
          metadataMessageId: 102,
          sizeMb: 2.5,
          mimeType: 'application/pdf',
          uploadedAt: DateTime(2026, 1, 2),
          chunkCount: 1,
          sha256Hash: '',
        ),
      ];

      repo = _FakeNavigationStorageRepo(folders, files);
    });

    test(
        'LoadDirectory loads target folder immediately and does not show root items',
        () async {
      final bloc = BrowserBloc(repo);

      // Initial load at root
      bloc.add(LoadDirectory());
      await pumpEventQueue();

      expect(bloc.state.currentFolderId, isNull);
      expect(bloc.state.folders.length, 1);
      expect(bloc.state.folders.first.name, 'Documents');
      expect(bloc.state.files.length, 1);
      expect(bloc.state.files.first.name, 'root_note.txt');

      // Navigate to Documents folder
      bloc.add(LoadDirectory(folderId: 'folder-root-1'));
      await pumpEventQueue();

      expect(bloc.state.currentFolderId, 'folder-root-1');
      // Must contain subfolder 'Projects' and NOT 'Documents'
      expect(bloc.state.folders.length, 1);
      expect(bloc.state.folders.first.name, 'Projects');
      // Must contain 'report.pdf' and NOT 'root_note.txt'
      expect(bloc.state.files.length, 1);
      expect(bloc.state.files.first.name, 'report.pdf');

      await bloc.close();
    });

    test(
        'LocalContentsChanged updates items from local repository without sync',
        () async {
      final bloc = BrowserBloc(repo);

      bloc.add(LoadDirectory(folderId: 'folder-root-1'));
      await pumpEventQueue();

      expect(bloc.state.files.length, 1);

      // Add a new file locally
      files.add(FileRecord(
        fileId: 'doc-file-2',
        name: 'budget.xlsx',
        folderId: 'folder-root-1',
        metadataMessageId: 103,
        sizeMb: 0.8,
        mimeType: 'application/octet-stream',
        uploadedAt: DateTime(2026, 1, 3),
        chunkCount: 1,
        sha256Hash: '',
      ));

      // Trigger local contents change
      bloc.add(const LocalContentsChanged());
      await pumpEventQueue();

      expect(bloc.state.files.length, 2);
      expect(bloc.state.files.any((f) => f.name == 'budget.xlsx'), isTrue);

      await bloc.close();
    });

    test('Folder and FolderRecord preserve itemCount correctly', () {
      final folder = Folder(
        id: 'f-1',
        name: 'Work',
        createdAt: DateTime(2026, 1, 1),
        itemCount: 42,
      );
      expect(folder.itemCount, 42);

      final json = folder.toJson();
      expect(json['item_count'], 42);

      final parsed = Folder.fromJson(json);
      expect(parsed.itemCount, 42);

      final record = FolderRecord.fromFolder(parsed);
      expect(record.itemCount, 42);

      final roundtrip = record.toFolder();
      expect(roundtrip.itemCount, 42);
    });
  });
}
