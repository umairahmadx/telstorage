/// File: clean_architecture_test.dart
/// Description: Clean Architecture tests verifying domain use cases, repositories, and Result monad.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/events/domain_event_bus.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';
import 'package:telstorage/features/storage/domain/usecases/download_file_usecase.dart';
import 'package:telstorage/features/storage/domain/usecases/generate_web_share_usecase.dart';

class MockStorageRepository implements StorageRepositoryContract {
  bool downloadEnqueued = false;
  bool shareEnqueued = false;
  bool shouldFail = false;

  @override
  List<FileRecord> get currentFiles => [];

  @override
  List<FolderRecord> get currentFolders => [];

  @override
  FileRecord? getFile(String fileId) => null;

  @override
  FolderRecord? getFolder(String folderId) => null;

  @override
  Future<Result<String>> createFolder(String name, {String? parentId}) async =>
      const Success('folder_123');

  @override
  Future<Result<void>> renameFolder(String folderId, String newName) async =>
      const Success(null);

  @override
  Future<Result<void>> deleteFolder(String folderId) async =>
      const Success(null);

  @override
  Future<Result<void>> renameFile(String fileId, String newName) async =>
      const Success(null);

  @override
  Future<Result<void>> copyFile(String fileId, String? targetFolderId) async =>
      const Success(null);

  @override
  Future<Result<void>> deleteFile(String fileId) async =>
      const Success(null);

  @override
  Future<Result<void>> enqueueDownload(FileRecord file) async {
    if (shouldFail) return const Failure(UnknownFailure('Download failed test'));
    downloadEnqueued = true;
    return const Success(null);
  }

  @override
  Future<Result<void>> enqueueWebShare(
    FileRecord file, {
    String? password,
    int? expiryDays,
    String? vanitySlug,
  }) async {
    if (shouldFail) return const Failure(UnknownFailure('Share failed test'));
    shareEnqueued = true;
    return const Success(null);
  }
}

class DownloadOnlyFake implements DownloadEnqueuer {
  bool called = false;

  @override
  Future<Result<void>> enqueueDownload(FileRecord file) async {
    called = true;
    return const Success(null);
  }
}

class WebShareOnlyFake implements WebShareEnqueuer {
  bool called = false;

  @override
  Future<Result<void>> enqueueWebShare(
    FileRecord file, {
    String? password,
    int? expiryDays,
    String? vanitySlug,
  }) async {
    called = true;
    return const Success(null);
  }
}

void main() {
  group('Result<T> & StorageFailure Tests', () {
    test('Success returns data and fold correctly', () {
      const result = Success<String>('hello');
      expect(result.isSuccess, true);
      expect(result.isFailure, false);
      expect(result.dataOrNull, 'hello');

      final value = result.fold(
        (data) => 'Data: $data',
        (failure) => 'Error',
      );
      expect(value, 'Data: hello');
    });

    test('Failure returns failure and fold correctly', () {
      const result = Failure<String>(NetworkFailure('No connection'));
      expect(result.isSuccess, false);
      expect(result.isFailure, true);
      expect(result.failureOrNull?.message, 'No connection');

      final value = result.fold(
        (data) => 'Data: $data',
        (failure) => failure.message,
      );
      expect(value, 'No connection');
    });
  });

  group('Domain Use Cases Tests', () {
    late MockStorageRepository mockRepo;
    late FileRecord dummyFile;

    setUp(() {
      mockRepo = MockStorageRepository();
      dummyFile = FileRecord(
        fileId: 'file_1',
        name: 'test.pdf',
        metadataMessageId: 100,
        sizeMb: 1.5,
        mimeType: 'application/pdf',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'abc123hash',
      );
    });

    test('DownloadFileUseCase executes successfully', () async {
      final useCase = DownloadFileUseCase(mockRepo);
      final result = await useCase(dummyFile);
      expect(result.isSuccess, true);
      expect(mockRepo.downloadEnqueued, true);
    });

    test('DownloadFileUseCase catches exception and returns Failure', () async {
      mockRepo.shouldFail = true;
      final useCase = DownloadFileUseCase(mockRepo);
      final result = await useCase(dummyFile);
      expect(result.isFailure, true);
      expect(result.failureOrNull?.message, contains('Download failed test'));
    });

    test('GenerateWebShareUseCase executes with vanitySlug params successfully', () async {
      final useCase = GenerateWebShareUseCase(mockRepo);
      final result = await useCase(GenerateWebShareParams(
        file: dummyFile,
        vanitySlug: 'my-custom-doc',
      ));
      expect(result.isSuccess, true);
      expect(mockRepo.shareEnqueued, true);
    });

    test('use cases depend on segregated capabilities, not the full repository', () async {
      final download = DownloadOnlyFake();
      final share = WebShareOnlyFake();

      expect((await DownloadFileUseCase(download)(dummyFile)).isSuccess, true);
      expect(
        (await GenerateWebShareUseCase(share)(
          GenerateWebShareParams(file: dummyFile, expiryDays: 7),
        )).isSuccess,
        true,
      );
      expect(download.called, true);
      expect(share.called, true);
    });
  });

  group('Sealed Result contract tests', () {
    test('all result branches are handled without exceptions', () {
      String describe(Result<int> result) => switch (result) {
        Success<int>(data: final value) => 'value:$value',
        Failure<int>(failure: final error) => 'error:${error.message}',
      };

      expect(describe(const Success(42)), 'value:42');
      expect(describe(const Failure(NetworkFailure('offline'))), 'error:offline');
    });
  });

  group('DomainEventBus Tests', () {
    test('DomainEventBus emits and receives FileUploadedEvent', () async {
      final bus = DomainEventBus.instance;
      final dummyFile = FileRecord(
        fileId: 'file_99',
        name: 'photo.png',
        metadataMessageId: 200,
        sizeMb: 0.5,
        mimeType: 'image/png',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'hash_xyz',
      );

      final eventFuture = bus.on<FileUploadedEvent>().first;
      bus.fire(FileUploadedEvent(dummyFile));

      final event = await eventFuture;
      expect(event.file.name, 'photo.png');
    });

    test('DomainEventBus emits FolderCreatedEvent', () async {
      final bus = DomainEventBus.instance;
      final eventFuture = bus.on<FolderCreatedEvent>().first;
      bus.fire(FolderCreatedEvent('folder_abc', 'My Documents'));

      final event = await eventFuture;
      expect(event.folderId, 'folder_abc');
      expect(event.name, 'My Documents');
    });

    test('DomainEventBus emits FileDeletedEvent', () async {
      final bus = DomainEventBus.instance;
      final eventFuture = bus.on<FileDeletedEvent>().first;
      bus.fire(FileDeletedEvent('file_42'));

      final event = await eventFuture;
      expect(event.fileId, 'file_42');
    });

    test('DomainEventBus emits WebShareCompletedEvent', () async {
      final bus = DomainEventBus.instance;
      final eventFuture = bus.on<WebShareCompletedEvent>().first;
      bus.fire(WebShareCompletedEvent('file_55', 'https://storage.to/abc'));

      final event = await eventFuture;
      expect(event.fileId, 'file_55');
      expect(event.shareUrl, 'https://storage.to/abc');
    });

    test('DomainEventBus type-filtered stream ignores unrelated events', () async {
      final bus = DomainEventBus.instance;

      final deletedEvents = <FileDeletedEvent>[];
      final sub = bus.on<FileDeletedEvent>().listen(deletedEvents.add);

      bus.fire(FolderCreatedEvent('f1', 'Test'));
      bus.fire(FileRenamedEvent('f2', 'new.txt'));
      bus.fire(FileDeletedEvent('f3'));

      await Future.delayed(Duration.zero);

      expect(deletedEvents.length, 1);
      expect(deletedEvents.first.fileId, 'f3');
      await sub.cancel();
    });

    test('DomainEventBus broadcasts one event to multiple typed listeners', () async {
      final bus = DomainEventBus.instance;
      final first = bus.on<FolderDeletedEvent>().first;
      final second = bus.on<FolderDeletedEvent>().first;

      bus.fire(FolderDeletedEvent('folder_shared'));

      expect((await first).folderId, 'folder_shared');
      expect((await second).folderId, 'folder_shared');
    });
  });
}
