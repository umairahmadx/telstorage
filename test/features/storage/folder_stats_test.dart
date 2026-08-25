/*
 * File: folder_stats_test.dart
 * Description: Unit tests verifying recursive FolderStats calculations, size formatting, and tree traversal.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/folder_stats.dart';

void main() {
  group('FolderStats Model & Size Formatting Tests', () {
    test('TC-01: Empty folder formatting returns KB', () {
      const stats = FolderStats(
        fileCount: 0,
        subfolderCount: 0,
        totalSizeMb: 0.0,
      );

      expect(stats.formattedSize, equals('0.0 KB'));
      expect(stats.fileCount, equals(0));
      expect(stats.subfolderCount, equals(0));
    });

    test('TC-02: Small size under 1MB formats in KB', () {
      const stats = FolderStats(
        fileCount: 3,
        subfolderCount: 1,
        totalSizeMb: 0.5,
      );

      expect(stats.formattedSize, equals('512 KB'));
    });

    test('TC-03: Multi-megabyte size formats in MB', () {
      const stats = FolderStats(
        fileCount: 12,
        subfolderCount: 2,
        totalSizeMb: 45.25,
      );

      expect(stats.formattedSize, equals('45.25 MB'));
    });

    test('TC-04: Gigabyte size formats in GB', () {
      const stats = FolderStats(
        fileCount: 150,
        subfolderCount: 8,
        totalSizeMb: 2048.0,
      );

      expect(stats.formattedSize, equals('2.00 GB'));
    });
  });

  group('Recursive Folder Tree & Statistics Logic', () {
    test('TC-05: Recursively computes file counts, subfolders, and size across nested hierarchy', () {
      // Mock hierarchy:
      // Root Folder (id: 'f1')
      //   ├── File 1 (10 MB, folderId: 'f1')
      //   ├── Subfolder 1 (id: 'f2', parentId: 'f1')
      //   │     ├── File 2 (5 MB, folderId: 'f2')
      //   │     └── Subfolder 2 (id: 'f3', parentId: 'f2')
      //   │           └── File 3 (20 MB, folderId: 'f3')
      //   └── Subfolder 3 (id: 'f4', parentId: 'f1')
      //         └── File 4 (15 MB, folderId: 'f4')

      final folders = [
        FolderRecord(id: 'f1', name: 'Root', createdAt: DateTime.now()),
        FolderRecord(id: 'f2', name: 'Sub 1', parentId: 'f1', createdAt: DateTime.now()),
        FolderRecord(id: 'f3', name: 'Sub 2', parentId: 'f2', createdAt: DateTime.now()),
        FolderRecord(id: 'f4', name: 'Sub 3', parentId: 'f1', createdAt: DateTime.now()),
        FolderRecord(id: 'f5_unrelated', name: 'Other', createdAt: DateTime.now()),
      ];

      final files = [
        FileRecord(
          fileId: 'file_1',
          metadataMessageId: 1,
          metadataFileId: 'meta_1',
          name: 'doc1.pdf',
          sizeMb: 10.0,
          mimeType: 'application/pdf',
          uploadedAt: DateTime.now(),
          folderId: 'f1',
          chunkCount: 1,
          sha256Hash: 'hash1',
        ),
        FileRecord(
          fileId: 'file_2',
          metadataMessageId: 2,
          metadataFileId: 'meta_2',
          name: 'doc2.pdf',
          sizeMb: 5.0,
          mimeType: 'application/pdf',
          uploadedAt: DateTime.now(),
          folderId: 'f2',
          chunkCount: 1,
          sha256Hash: 'hash2',
        ),
        FileRecord(
          fileId: 'file_3',
          metadataMessageId: 3,
          metadataFileId: 'meta_3',
          name: 'video.mp4',
          sizeMb: 20.0,
          mimeType: 'video/mp4',
          uploadedAt: DateTime.now(),
          folderId: 'f3',
          chunkCount: 1,
          sha256Hash: 'hash3',
        ),
        FileRecord(
          fileId: 'file_4',
          metadataMessageId: 4,
          metadataFileId: 'meta_4',
          name: 'archive.zip',
          sizeMb: 15.0,
          mimeType: 'application/zip',
          uploadedAt: DateTime.now(),
          folderId: 'f4',
          chunkCount: 1,
          sha256Hash: 'hash4',
        ),
        FileRecord(
          fileId: 'file_5_unrelated',
          metadataMessageId: 5,
          metadataFileId: 'meta_5',
          name: 'other.txt',
          sizeMb: 100.0,
          mimeType: 'text/plain',
          uploadedAt: DateTime.now(),
          folderId: 'f5_unrelated',
          chunkCount: 1,
          sha256Hash: 'hash5',
        ),
      ];

      Set<String> folderTreeIds(String folderId) {
        final ids = <String>{};
        void collect(String id) {
          if (!ids.add(id)) return;
          for (final child in folders.where((f) => f.parentId == id)) {
            collect(child.id);
          }
        }
        collect(folderId);
        return ids;
      }

      FolderStats calculateStats(String folderId) {
        final treeIds = folderTreeIds(folderId);
        final containedFiles = files.where((f) => treeIds.contains(f.folderId)).toList();
        final subfolderCount = treeIds.length - 1;
        final totalSizeMb = containedFiles.fold<double>(0.0, (sum, f) => sum + f.sizeMb);
        return FolderStats(
          fileCount: containedFiles.length,
          subfolderCount: subfolderCount > 0 ? subfolderCount : 0,
          totalSizeMb: totalSizeMb,
        );
      }

      // Root folder stats (f1)
      final rootStats = calculateStats('f1');
      expect(rootStats.fileCount, equals(4)); // files 1, 2, 3, 4
      expect(rootStats.subfolderCount, equals(3)); // f2, f3, f4
      expect(rootStats.totalSizeMb, equals(50.0)); // 10 + 5 + 20 + 15
      expect(rootStats.formattedSize, equals('50.00 MB'));

      // Subfolder 1 stats (f2)
      final sub1Stats = calculateStats('f2');
      expect(sub1Stats.fileCount, equals(2)); // files 2, 3
      expect(sub1Stats.subfolderCount, equals(1)); // f3
      expect(sub1Stats.totalSizeMb, equals(25.0)); // 5 + 20
      expect(sub1Stats.formattedSize, equals('25.00 MB'));

      // Leaf subfolder stats (f3)
      final leafStats = calculateStats('f3');
      expect(leafStats.fileCount, equals(1)); // file 3
      expect(leafStats.subfolderCount, equals(0));
      expect(leafStats.totalSizeMb, equals(20.0));
    });
  });
}
