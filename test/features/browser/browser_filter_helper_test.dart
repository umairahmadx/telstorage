/*
 * File: browser_filter_helper_test.dart
 * Description: Unit tests verifying BrowserFilterHelper category matching and directory filtering across all file categories.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_event.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/viewmodel/browser_filter_helper.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';

class _FakeStorageRepo implements StorageRepositoryContract {
  final List<FileRecord> files;
  final List<FolderRecord> folders;

  _FakeStorageRepo({required this.files, this.folders = const []});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  List<FileRecord> getFiles(String? folderId) => files;

  @override
  List<FolderRecord> getFolders(String? parentId) => folders;

  @override
  int getFilesInFolderCount(String folderId) => 0;
}

void main() {
  final imgFile = FileRecord(
    fileId: 'img_1',
    name: 'photo.jpg',
    metadataMessageId: 1,
    sizeMb: 2.5,
    mimeType: 'image/jpeg',
    uploadedAt: DateTime.now(),
    chunkCount: 1,
    sha256Hash: 'hash1',
  );

  final vidFile = FileRecord(
    fileId: 'vid_1',
    name: 'movie.mp4',
    metadataMessageId: 2,
    sizeMb: 50.0,
    mimeType: 'video/mp4',
    uploadedAt: DateTime.now(),
    chunkCount: 2,
    sha256Hash: 'hash2',
  );

  final docFile = FileRecord(
    fileId: 'doc_1',
    name: 'report.pdf',
    metadataMessageId: 3,
    sizeMb: 1.0,
    mimeType: 'application/pdf',
    uploadedAt: DateTime.now(),
    chunkCount: 1,
    sha256Hash: 'hash3',
  );

  final audioFile = FileRecord(
    fileId: 'aud_1',
    name: 'podcast.mp3',
    metadataMessageId: 4,
    sizeMb: 15.0,
    mimeType: 'audio/mpeg',
    uploadedAt: DateTime.now(),
    chunkCount: 1,
    sha256Hash: 'hash4',
  );

  final archiveFile = FileRecord(
    fileId: 'arc_1',
    name: 'backup.zip',
    metadataMessageId: 5,
    sizeMb: 100.0,
    mimeType: 'application/zip',
    uploadedAt: DateTime.now(),
    chunkCount: 4,
    sha256Hash: 'hash5',
  );

  group('BrowserFilterHelper.matchesCategory Unit Tests', () {
    test('Image file matches image and images category filter', () {
      expect(BrowserFilterHelper.matchesCategory(imgFile, AppConstants.categoryImages), isTrue);
      expect(BrowserFilterHelper.matchesCategory(imgFile, 'images'), isTrue);
      expect(BrowserFilterHelper.matchesCategory(imgFile, AppConstants.categoryVideos), isFalse);
      expect(BrowserFilterHelper.matchesCategory(imgFile, AppConstants.categoryDocuments), isFalse);
      expect(BrowserFilterHelper.matchesCategory(imgFile, AppConstants.categoryAudio), isFalse);
      expect(BrowserFilterHelper.matchesCategory(imgFile, AppConstants.categoryArchives), isFalse);
    });

    test('Video file matches video and videos category filter', () {
      expect(BrowserFilterHelper.matchesCategory(vidFile, AppConstants.categoryVideos), isTrue);
      expect(BrowserFilterHelper.matchesCategory(vidFile, 'videos'), isTrue);
      expect(BrowserFilterHelper.matchesCategory(vidFile, AppConstants.categoryImages), isFalse);
      expect(BrowserFilterHelper.matchesCategory(vidFile, AppConstants.categoryAudio), isFalse);
    });

    test('Audio file matches audio category filter', () {
      expect(BrowserFilterHelper.matchesCategory(audioFile, AppConstants.categoryAudio), isTrue);
      expect(BrowserFilterHelper.matchesCategory(audioFile, 'audio'), isTrue);
      expect(BrowserFilterHelper.matchesCategory(audioFile, AppConstants.categoryVideos), isFalse);
      expect(BrowserFilterHelper.matchesCategory(audioFile, AppConstants.categoryImages), isFalse);
    });

    test('Document file matches document and docs category filter', () {
      expect(BrowserFilterHelper.matchesCategory(docFile, AppConstants.categoryDocuments), isTrue);
      expect(BrowserFilterHelper.matchesCategory(docFile, 'docs'), isTrue);
      expect(BrowserFilterHelper.matchesCategory(docFile, AppConstants.categoryImages), isFalse);
      expect(BrowserFilterHelper.matchesCategory(docFile, AppConstants.categoryArchives), isFalse);
    });

    test('Archive file matches archive and archives category filter', () {
      expect(BrowserFilterHelper.matchesCategory(archiveFile, AppConstants.categoryArchives), isTrue);
      expect(BrowserFilterHelper.matchesCategory(archiveFile, 'archives'), isTrue);
      expect(BrowserFilterHelper.matchesCategory(archiveFile, AppConstants.categoryDocuments), isFalse);
      expect(BrowserFilterHelper.matchesCategory(archiveFile, AppConstants.categoryAudio), isFalse);
    });
  });

  group('BrowserFilterHelper.loadAndFilterContents Unit Tests', () {
    test('Filtering by category isolates matching files and suppresses folders', () {
      final repo = _FakeStorageRepo(
        files: [imgFile, vidFile, docFile, audioFile, archiveFile],
        folders: [
          FolderRecord(id: 'f1', name: 'Subfolder', createdAt: DateTime.now()),
        ],
      );

      final imagesResult = BrowserFilterHelper.loadAndFilterContents(
        repository: repo,
        folderId: null,
        category: AppConstants.categoryImages,
        searchQuery: '',
        sortOption: BrowserSortOption.name,
        sortAscending: true,
      );

      expect(imagesResult.folders, isEmpty);
      expect(imagesResult.files.map((f) => f.fileId), [imgFile.fileId]);

      final audioResult = BrowserFilterHelper.loadAndFilterContents(
        repository: repo,
        folderId: null,
        category: AppConstants.categoryAudio,
        searchQuery: '',
        sortOption: BrowserSortOption.name,
        sortAscending: true,
      );

      expect(audioResult.folders, isEmpty);
      expect(audioResult.files.map((f) => f.fileId), [audioFile.fileId]);

      final archiveResult = BrowserFilterHelper.loadAndFilterContents(
        repository: repo,
        folderId: null,
        category: AppConstants.categoryArchives,
        searchQuery: '',
        sortOption: BrowserSortOption.name,
        sortAscending: true,
      );

      expect(archiveResult.folders, isEmpty);
      expect(archiveResult.files.map((f) => f.fileId), [archiveFile.fileId]);
    });
  });
}
