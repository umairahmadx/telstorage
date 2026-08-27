/*
 * File: folder_traversal_service_test.dart
 * Description: Unit tests for FolderTraversalService verifying recursive BFS traversal, path resolution, and multi-selection resolution.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/folder_traversal_service.dart';

void main() {
  final now = DateTime(2026, 8, 27);
  final rootFolder = FolderRecord(
    id: 'f1',
    name: 'Documents',
    parentId: null,
    createdAt: now,
  );
  final subFolder = FolderRecord(
    id: 'f2',
    name: 'Work',
    parentId: 'f1',
    createdAt: now,
  );
  final otherFolder = FolderRecord(
    id: 'f3',
    name: 'Photos',
    parentId: null,
    createdAt: now,
  );

  final file1 = FileRecord(
    fileId: 'doc1',
    name: 'invoice.pdf',
    folderId: 'f2',
    sizeMb: 1.5,
    mimeType: 'application/pdf',
    uploadedAt: now,
    chunkCount: 1,
    sha256Hash: '',
    metadataMessageId: 0,
  );
  final file2 = FileRecord(
    fileId: 'doc2',
    name: 'notes.txt',
    folderId: 'f1',
    sizeMb: 0.5,
    mimeType: 'text/plain',
    uploadedAt: now,
    chunkCount: 1,
    sha256Hash: '',
    metadataMessageId: 0,
  );
  final file3 = FileRecord(
    fileId: 'img1',
    name: 'vacation.jpg',
    folderId: 'f3',
    sizeMb: 3.0,
    mimeType: 'image/jpeg',
    uploadedAt: now,
    chunkCount: 1,
    sha256Hash: '',
    metadataMessageId: 0,
  );

  final allFolders = [rootFolder, subFolder, otherFolder];
  final allFiles = [file1, file2, file3];

  group('FolderTraversalService.resolveDescendants', () {
    test('TC-01: Resolves nested files and relative paths correctly', () {
      final items = FolderTraversalService.resolveDescendants(
        targetFolderId: 'f1',
        allFolders: allFolders,
        allFiles: allFiles,
      );

      expect(items.length, equals(2));
      final invoice = items.firstWhere((i) => i.file.fileId == 'doc1');
      expect(invoice.relativePath, equals('Documents/Work/invoice.pdf'));
      expect(invoice.subpath, equals('Documents/Work'));

      final notes = items.firstWhere((i) => i.file.fileId == 'doc2');
      expect(notes.relativePath, equals('Documents/notes.txt'));
      expect(notes.subpath, equals('Documents'));
    });

    test('TC-02: Returns empty list for non-existent folder id', () {
      final items = FolderTraversalService.resolveDescendants(
        targetFolderId: 'non_existent',
        allFolders: allFolders,
        allFiles: allFiles,
      );
      expect(items, isEmpty);
    });
  });

  group('FolderTraversalService.resolveMultiSelection', () {
    test(
        'TC-03: Resolves combined direct files and folder selections without duplicate',
        () {
      final items = FolderTraversalService.resolveMultiSelection(
        folderIds: {'f1'},
        fileIds: {'img1', 'doc2'}, // doc2 is inside f1, should not duplicate
        allFolders: allFolders,
        allFiles: allFiles,
      );

      expect(items.length, equals(3));
      final fileIds = items.map((i) => i.file.fileId).toSet();
      expect(fileIds, containsAll({'doc1', 'doc2', 'img1'}));
    });
  });

  group('FolderTraversalService.calculateStats', () {
    test('TC-04: Computes total files and aggregate size accurately', () {
      final items = FolderTraversalService.resolveDescendants(
        targetFolderId: 'f1',
        allFolders: allFolders,
        allFiles: allFiles,
      );
      final stats = FolderTraversalService.calculateStats(items);
      expect(stats.totalFiles, equals(2));
      expect(stats.totalSizeMb, closeTo(2.0, 0.001));
    });
  });
}
