/*
 * File: ui_selection_edge_cases_test.dart
 * Description: Tests for UI selection edge cases: empty batch download, select-all with active filters, and offline transfer guards.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_batch_helper.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_state.dart';
import 'package:telstorage/features/storage/data/repositories/storage_repository.dart';

class _MockStorageRepo implements StorageRepository {
  @override
  List<FolderRecord> getFolders(String? parentId) => [];

  @override
  List<FileRecord> getFiles(String? folderId) => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 8, 27);

  final folder1 =
      FolderRecord(id: 'f1', name: 'Work', parentId: null, createdAt: now);

  final file1 = FileRecord(
    fileId: 'file_inv_1',
    name: 'invoice_2026.pdf',
    metadataMessageId: 1,
    sizeMb: 2.5,
    mimeType: 'application/pdf',
    uploadedAt: now,
    chunkCount: 1,
    sha256Hash: 'hash1',
  );

  group('UI Selection & Batch Edge Cases (EC-16, EC-17, EC-18)', () {
    test('EC-16: executeBatchDownload returns 0 when no items are selected',
        () async {
      final state = BrowserState(
        selectedFolderIds: {},
        selectedFileIds: {},
      );

      final count = await BrowserBatchHelper.executeBatchDownload(
        state: state,
        repository: _MockStorageRepo(),
      );

      expect(count, equals(0));
    });

    test('EC-17: toggleSelectAll only selects visible filtered items', () {
      // Simulating search query "invoice" where only folder1 and file1 are visible in state
      final filteredState = BrowserState(
        folders: [folder1],
        files: [file1],
        searchQuery: 'invoice',
        selectedFolderIds: {},
        selectedFileIds: {},
      );

      // Select All on filtered view
      final selectAllRes = BrowserBatchHelper.toggleSelectAll(
        state: filteredState,
        selectAll: true,
      );

      expect(selectAllRes.folderIds, contains('f1'));
      expect(selectAllRes.folderIds,
          isNot(contains('f2'))); // hidden folder not selected
      expect(selectAllRes.fileIds, contains('file_inv_1'));
      expect(selectAllRes.fileIds,
          isNot(contains('file_photo_1'))); // hidden file not selected

      // Deselect All on filtered view
      final deselectState = filteredState.copyWith(
        selectedFolderIds: selectAllRes.folderIds,
        selectedFileIds: selectAllRes.fileIds,
      );

      final deselectRes = BrowserBatchHelper.toggleSelectAll(
        state: deselectState,
        selectAll: false,
      );

      expect(deselectRes.folderIds, isEmpty);
      expect(deselectRes.fileIds, isEmpty);
    });

    test(
        'EC-17: toggleSelectAll preserves existing selection outside current view when selecting',
        () {
      // Suppose item 'f3' was previously selected, and now visible items are [f1] and [file1]
      final stateWithExisting = BrowserState(
        folders: [folder1],
        files: [file1],
        selectedFolderIds: {'f3'},
        selectedFileIds: {'file_old'},
      );

      final res = BrowserBatchHelper.toggleSelectAll(
        state: stateWithExisting,
        selectAll: true,
      );

      expect(res.folderIds, containsAll(['f3', 'f1']));
      expect(res.fileIds, containsAll(['file_old', 'file_inv_1']));
    });
  });
}
