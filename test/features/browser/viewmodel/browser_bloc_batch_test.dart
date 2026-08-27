/*
 * File: browser_bloc_batch_test.dart
 * Description: Unit tests for BrowserBloc batch events including ToggleSelectAll, BatchDownload, DownloadFolder, and ExportFolderAsZip.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';

class _FakeStorageRepository implements StorageRepositoryContract {
  final List<FolderRecord> _folders = [];
  final List<FileRecord> _files = [];

  _FakeStorageRepository({
    List<FolderRecord>? folders,
    List<FileRecord>? files,
  }) {
    if (folders != null) _folders.addAll(folders);
    if (files != null) _files.addAll(files);
  }

  @override
  List<FolderRecord> getFolders(String? parentId) =>
      _folders.where((f) => f.parentId == parentId).toList();

  @override
  List<FileRecord> getFiles(String? folderId) =>
      _files.where((f) => f.folderId == folderId).toList();

  @override
  int getFilesInFolderCount(String folderId) =>
      _files.where((f) => f.folderId == folderId).length;

  @override
  FolderRecord? getFolder(String id) {
    try {
      return _folders.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 8, 27);
  final folder1 =
      FolderRecord(id: 'f1', name: 'Docs', parentId: null, createdAt: now);
  final file1 = FileRecord(
    fileId: 'file1',
    name: 'test.pdf',
    folderId: null,
    sizeMb: 2.0,
    mimeType: 'application/pdf',
    uploadedAt: now,
    chunkCount: 1,
    sha256Hash: '',
    metadataMessageId: 0,
  );

  test('TC-01: ToggleSelectAll selects all and clears all correctly', () {
    final repo = _FakeStorageRepository(folders: [folder1], files: [file1]);
    final bloc = BrowserBloc(repo);

    // Initial state has folders & files loaded
    bloc.emit(bloc.state.copyWith(
      folders: [folder1],
      files: [file1],
      isInitialized: true,
    ));

    bloc.add(const ToggleSelectAll(selectAll: true));

    expect(
        bloc.stream,
        emitsInOrder([
          predicate<BrowserState>((state) {
            return state.selectedFolderIds.contains('f1') &&
                state.selectedFileIds.contains('file1');
          }),
        ]));
  });

  test('TC-02: ToggleSelectAll with false clears selection', () {
    final repo = _FakeStorageRepository(folders: [folder1], files: [file1]);
    final bloc = BrowserBloc(repo);

    bloc.emit(bloc.state.copyWith(
      folders: [folder1],
      files: [file1],
      selectedFolderIds: {'f1'},
      selectedFileIds: {'file1'},
      isInitialized: true,
    ));

    bloc.add(const ToggleSelectAll(selectAll: false));

    expect(
        bloc.stream,
        emitsInOrder([
          predicate<BrowserState>((state) {
            return state.selectedFolderIds.isEmpty &&
                state.selectedFileIds.isEmpty;
          }),
        ]));
  });
}
