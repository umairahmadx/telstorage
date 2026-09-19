/*
 * File: metadata_sync_coordinator_test.dart
 * Description: Unit tests validating debounced metadata sync, coalesced partition updates, explicit flush, and net-zero burst cancelation.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/services/metadata_partition_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/metadata_sync_coordinator.dart';
import 'package:telstorage/core/services/telegram_service.dart';

class _FakeTelegramService extends TelegramService {}

class _MockMetadataService extends MetadataService {
  AppMetadata currentMeta;
  int updateCallCount = 0;
  int fetchCallCount = 0;

  _MockMetadataService(this.currentMeta) : super(_FakeTelegramService());

  @override
  Future<AppMetadata> fetch() async {
    fetchCallCount++;
    return currentMeta;
  }

  @override
  Future<void> update(AppMetadata meta) async {
    updateCallCount++;
    currentMeta = meta;
  }
}

class _MockPartitionService extends MetadataPartitionService {
  final Map<String, List<FileRef>> partitions = {};
  int saveCallCount = 0;
  int removeCallCount = 0;

  _MockPartitionService() : super(_FakeTelegramService());

  @override
  Future<void> saveFileRefsToPartition(
    AppMetadata meta,
    String folderId,
    List<FileRef> newRefs,
  ) async {
    saveCallCount++;
    final list = partitions.putIfAbsent(folderId, () => []);
    for (final ref in newRefs) {
      list.removeWhere((f) => f.fileId == ref.fileId);
      list.add(ref);
    }
  }

  @override
  Future<void> removeFileRefFromPartition(
    AppMetadata meta,
    String folderId,
    String fileId,
  ) async {
    removeCallCount++;
    final list = partitions[folderId];
    if (list != null) {
      list.removeWhere((f) => f.fileId == fileId);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppMetadata initialMeta;
  late _MockMetadataService mockMetadataService;
  late _MockPartitionService mockPartitionService;
  late MetadataSyncCoordinator coordinator;

  setUp(() {
    initialMeta = AppMetadata(
      owner: 'test_owner',
      storageUsedMb: 0.0,
      totalFiles: 0,
      metadataMessageId: 1,
      folders: [],
      recentFiles: [],
      folderPartitionsMap: {},
      categories: {},
      lastSynced: DateTime.now(),
    );
    mockMetadataService = _MockMetadataService(initialMeta);
    mockPartitionService = _MockPartitionService();
    coordinator = MetadataSyncCoordinator(
      mockMetadataService,
      mockPartitionService,
      debounceDuration: const Duration(milliseconds: 100),
    );
  });

  tearDown(() {
    coordinator.dispose();
  });

  group('MetadataSyncCoordinator Tests', () {
    test('TC-01: Rapid consecutive additions coalesce into 1 partition write and 1 metadata update upon flush', () async {
      final file1 = {
        'file_id': 'f1',
        'name': 'file1.txt',
        'metadata_file_id': 'm1',
        'size_mb': 2.0,
        'mime_type': 'text/plain',
        'uploaded_at': DateTime.now().toIso8601String(),
        'chunk_count': 1,
        'sha256': 'hash1',
      };
      final file2 = {
        'file_id': 'f2',
        'name': 'file2.png',
        'metadata_file_id': 'm2',
        'size_mb': 5.0,
        'mime_type': 'image/png',
        'uploaded_at': DateTime.now().toIso8601String(),
        'chunk_count': 1,
        'sha256': 'hash2',
      };
      final file3 = {
        'file_id': 'f3',
        'name': 'file3.pdf',
        'metadata_file_id': 'm3',
        'size_mb': 3.0,
        'mime_type': 'application/pdf',
        'uploaded_at': DateTime.now().toIso8601String(),
        'chunk_count': 1,
        'sha256': 'hash3',
      };

      coordinator.enqueueAddFile(file1, debounce: false);
      coordinator.enqueueAddFile(file2, debounce: false);
      coordinator.enqueueAddFile(file3, debounce: false);

      expect(coordinator.hasPending, isTrue);
      expect(coordinator.pendingCount, equals(3));
      expect(mockMetadataService.updateCallCount, equals(0));
      expect(mockPartitionService.saveCallCount, equals(0));

      await coordinator.flush();

      expect(coordinator.hasPending, isFalse);
      expect(mockMetadataService.updateCallCount, equals(1));
      // All 3 files are in root partition, so exactly 1 partition save
      expect(mockPartitionService.saveCallCount, equals(1));
      expect(mockMetadataService.currentMeta.totalFiles, equals(3));
      expect(mockMetadataService.currentMeta.storageUsedMb, equals(10.0));
      expect(mockPartitionService.partitions[AppConstants.rootFolderPartitionId]?.length, equals(3));
    });

    test('TC-02: Debounce timer automatically triggers flush after duration expires', () async {
      final file1 = {
        'file_id': 'f_auto',
        'name': 'auto.txt',
        'metadata_file_id': 'm_auto',
        'size_mb': 1.0,
        'mime_type': 'text/plain',
        'uploaded_at': DateTime.now().toIso8601String(),
      };

      coordinator.enqueueAddFile(file1, debounce: true);
      expect(coordinator.hasPending, isTrue);
      expect(mockMetadataService.updateCallCount, equals(0));

      // Wait for debounce timer to expire
      await Future.delayed(const Duration(milliseconds: 150));

      expect(coordinator.hasPending, isFalse);
      expect(mockMetadataService.updateCallCount, equals(1));
      expect(mockPartitionService.saveCallCount, equals(1));
      expect(mockMetadataService.currentMeta.totalFiles, equals(1));
    });

    test('TC-03: Removals and additions across different folders batch into respective partitions', () async {
      // Pre-populate partition 'work_folder' with an existing file
      final existingWorkRef = FileRef(
        fileId: 'work_old',
        metaFileId: 'meta_old',
        name: 'old_doc.pdf',
        folderId: 'work_folder',
        sizeMb: 4.0,
        mimeType: 'application/pdf',
      );
      mockPartitionService.partitions['work_folder'] = [existingWorkRef];
      mockMetadataService.currentMeta.totalFiles = 1;
      mockMetadataService.currentMeta.storageUsedMb = 4.0;

      // Enqueue removal from 'work_folder'
      coordinator.enqueueRemoveFile(
        'work_old',
        4.0,
        'application/pdf',
        folderId: 'work_folder',
        debounce: false,
      );

      // Enqueue addition to 'photos_folder'
      final newPhoto = {
        'file_id': 'photo_1',
        'name': 'sunset.jpg',
        'metadata_file_id': 'meta_p1',
        'folder_id': 'photos_folder',
        'size_mb': 6.0,
        'mime_type': 'image/jpeg',
      };
      coordinator.enqueueAddFile(newPhoto, debounce: false);

      await coordinator.flush();

      expect(mockMetadataService.updateCallCount, equals(1));
      expect(mockPartitionService.removeCallCount, equals(1));
      expect(mockPartitionService.saveCallCount, equals(1));
      expect(mockPartitionService.partitions['work_folder']?.isEmpty, isTrue);
      expect(mockPartitionService.partitions['photos_folder']?.length, equals(1));
      expect(mockMetadataService.currentMeta.totalFiles, equals(1));
      expect(mockMetadataService.currentMeta.storageUsedMb, equals(6.0));
    });

    test('TC-04: Adding and removing the same file before flush cancels out (net-zero remote traffic)', () async {
      final transientFile = {
        'file_id': 'transient_01',
        'name': 'transient.tmp',
        'metadata_file_id': 'm_trans',
        'size_mb': 15.0,
        'mime_type': 'application/octet-stream',
      };

      coordinator.enqueueAddFile(transientFile, debounce: false);
      expect(coordinator.hasPending, isTrue);

      coordinator.enqueueRemoveFile(
        'transient_01',
        15.0,
        'application/octet-stream',
        debounce: false,
      );

      expect(coordinator.hasPending, isFalse);
      expect(coordinator.pendingCount, equals(0));

      await coordinator.flush();

      // Zero remote API calls made!
      expect(mockMetadataService.updateCallCount, equals(0));
      expect(mockPartitionService.saveCallCount, equals(0));
      expect(mockPartitionService.removeCallCount, equals(0));
    });

    test('TC-05: Updates (moves/renames) are coalesced into destination and source partitions', () async {
      final movedRef = FileRef(
        fileId: 'moved_file_01',
        metaFileId: 'meta_moved',
        name: 'moved_contract.pdf',
        folderId: 'dest_folder',
        sizeMb: 2.0,
        mimeType: 'application/pdf',
      );

      coordinator.enqueueUpdateFileRef(
        movedRef,
        oldFolderId: 'source_folder',
        folderChanged: true,
        debounce: false,
      );

      await coordinator.flush();

      expect(mockMetadataService.updateCallCount, equals(1));
      expect(mockPartitionService.removeCallCount, equals(1));
      expect(mockPartitionService.saveCallCount, equals(1));
      expect(mockPartitionService.partitions['dest_folder']?.first.fileId, equals('moved_file_01'));
    });
  });
}
