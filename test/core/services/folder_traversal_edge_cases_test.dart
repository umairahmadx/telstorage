/*
 * File: folder_traversal_edge_cases_test.dart
 * Description: Edge case tests simulating circular loops, path traversal, illegal characters, empty folders, and deep nesting.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/folder_traversal_service.dart';

void main() {
  final now = DateTime(2026, 8, 27);

  FileRecord makeFile(String id, String name, String? folderId, [double size = 1.0]) {
    return FileRecord(
      fileId: id,
      name: name,
      folderId: folderId,
      sizeMb: size,
      mimeType: 'text/plain',
      uploadedAt: now,
      chunkCount: 1,
      sha256Hash: '',
      metadataMessageId: 0,
    );
  }

  group('FolderTraversalService Edge Cases & Resilience Tests', () {
    test('EC-01: Circular reference in folder tree does not cause infinite loop', () {
      // Simulates corrupted tree: folderA -> folderB -> folderA
      final folderA = FolderRecord(id: 'fa', name: 'FolderA', parentId: 'fb', createdAt: now);
      final folderB = FolderRecord(id: 'fb', name: 'FolderB', parentId: 'fa', createdAt: now);
      final fileA = makeFile('f1', 'fileA.txt', 'fa');
      final fileB = makeFile('f2', 'fileB.txt', 'fb');

      final items = FolderTraversalService.resolveDescendants(
        targetFolderId: 'fa',
        allFolders: [folderA, folderB],
        allFiles: [fileA, fileB],
      );

      // Traversal terminates without stack overflow or infinite loop
      expect(items.isNotEmpty, isTrue);
      final visitedIds = items.map((i) => i.file.fileId).toSet();
      expect(visitedIds.contains('f1'), isTrue);
      expect(visitedIds.contains('f2'), isTrue);
    });

    test('EC-02: Empty folder returns empty list without error', () {
      final emptyFolder = FolderRecord(id: 'empty', name: 'EmptyFolder', parentId: null, createdAt: now);

      final items = FolderTraversalService.resolveDescendants(
        targetFolderId: 'empty',
        allFolders: [emptyFolder],
        allFiles: [],
      );

      expect(items, isEmpty);
      final stats = FolderTraversalService.calculateStats(items);
      expect(stats.totalFiles, equals(0));
      expect(stats.totalSizeMb, equals(0.0));
    });

    test('EC-03: Non-existent folder returns empty list', () {
      final items = FolderTraversalService.resolveDescendants(
        targetFolderId: 'missing_id',
        allFolders: [],
        allFiles: [],
      );

      expect(items, isEmpty);
    });

    test('EC-04: Path traversal sequences (..) in folder and file names are sanitized', () {
      final folder = FolderRecord(id: 'f1', name: '../../EvilFolder', parentId: null, createdAt: now);
      final file = makeFile('doc1', '../../etc/passwd.txt', 'f1');

      final items = FolderTraversalService.resolveDescendants(
        targetFolderId: 'f1',
        allFolders: [folder],
        allFiles: [file],
      );

      expect(items.length, equals(1));
      expect(items.first.relativePath, isNot(contains('..')));
      expect(items.first.subpath, isNot(contains('..')));
      expect(items.first.subpath, equals('EvilFolder'));
      expect(items.first.relativePath, equals('EvilFolder/etc_passwd.txt'));
    });

    test('EC-05: Illegal OS characters are sanitized from path segments', () {
      final folder = FolderRecord(id: 'f1', name: 'Work:Project*2026?|', parentId: null, createdAt: now);
      final file = makeFile('doc1', 'report<draft>v1".pdf', 'f1');

      final items = FolderTraversalService.resolveDescendants(
        targetFolderId: 'f1',
        allFolders: [folder],
        allFiles: [file],
      );

      expect(items.length, equals(1));
      expect(items.first.subpath, equals('Work_Project_2026'));
      expect(items.first.relativePath, equals('Work_Project_2026/report_draft_v1_.pdf'));
    });

    test('EC-06: Deeply nested folder hierarchy (> 10 levels) resolves accurately', () {
      final folders = <FolderRecord>[];
      const depth = 12;
      for (var i = 0; i < depth; i++) {
        folders.add(FolderRecord(
          id: 'level_$i',
          name: 'L$i',
          parentId: i == 0 ? null : 'level_${i - 1}',
          createdAt: now,
        ));
      }

      final leafFile = makeFile('leaf', 'leaf.txt', 'level_${depth - 1}', 3.5);

      final items = FolderTraversalService.resolveDescendants(
        targetFolderId: 'level_0',
        allFolders: folders,
        allFiles: [leafFile],
      );

      expect(items.length, equals(1));
      expect(items.first.relativePath, equals('L0/L1/L2/L3/L4/L5/L6/L7/L8/L9/L10/L11/leaf.txt'));
      expect(items.first.subpath, equals('L0/L1/L2/L3/L4/L5/L6/L7/L8/L9/L10/L11'));
      expect(items.first.file.sizeMb, equals(3.5));
    });

    test('EC-07: Multi-selection deduplicates when parent, child, and direct file are all selected', () {
      final parentFolder = FolderRecord(id: 'p1', name: 'Parent', parentId: null, createdAt: now);
      final childFolder = FolderRecord(id: 'c1', name: 'Child', parentId: 'p1', createdAt: now);
      final fileInChild = makeFile('f_child', 'nested.pdf', 'c1', 2.0);

      final items = FolderTraversalService.resolveMultiSelection(
        folderIds: {'p1', 'c1'},
        fileIds: {'f_child'},
        allFolders: [parentFolder, childFolder],
        allFiles: [fileInChild],
      );

      // Even though 'p1', 'c1', and 'f_child' were all selected, the file is resolved exactly ONCE
      expect(items.length, equals(1));
      expect(items.first.file.fileId, equals('f_child'));
    });
  });
}
