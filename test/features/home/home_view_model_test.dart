/*
 * File: home_view_model_test.dart
 * Description: Unit tests for HomeCubit verifying local-first 0ms emission, start-time in-flight cooldown locks, debounced reactivity, and lifecycle safety.
 */

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/models/web_share_job.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'package:telstorage/features/storage/data/repositories/storage_repository.dart';

class _FakeStorageRepository implements StorageRepository {
  int getQuotaCallCount = 0;
  int getMetadataCallCount = 0;
  Completer<Map<String, dynamic>>? quotaCompleter;
  Completer<AppMetadata>? metadataCompleter;

  List<FileRecord> mockRecentFiles = [
    FileRecord(
      fileId: 'f1',
      name: 'document.pdf',
      metadataMessageId: 1,
      sizeMb: 2.5,
      mimeType: 'application/pdf',
      uploadedAt: DateTime(2026, 1, 1),
      chunkCount: 1,
      sha256Hash: 'hash1',
    ),
  ];

  @override
  Future<String?> getUserEmail() async => 'test@example.com';

  @override
  List<FileRecord> getRecentFiles(int limit) => mockRecentFiles;

  @override
  int getTotalFiles() => 42;

  @override
  double getTotalSizeMb() => 150.5;

  @override
  int getTotalShares() => 7;

  @override
  int getTotalCompletedDownloads() => 12;

  @override
  Future<Map<String, dynamic>> getWebShareQuota() async {
    getQuotaCallCount++;
    if (quotaCompleter != null) {
      return quotaCompleter!.future;
    }
    return {'used_bandwidth_bytes': 1024, 'allowed_bandwidth_bytes': 2048};
  }

  @override
  Future<AppMetadata> getAppMetadata() async {
    getMetadataCallCount++;
    if (metadataCompleter != null) {
      return metadataCompleter!.future;
    }
    return AppMetadata(
      owner: 'test_owner',
      storageUsedMb: 150.5,
      totalFiles: 42,
      metadataMessageId: 999,
      folders: [],
      categories: {},
      lastSynced: DateTime(2026, 1, 1),
    );
  }

  @override
  List<FileRecord> get currentFiles => mockRecentFiles;

  @override
  List<FolderRecord> get currentFolders => [];

  @override
  List<FolderRecord> getFolders(String? parentId) => [];

  @override
  List<FileRecord> getFiles(String? folderId) => mockRecentFiles;

  @override
  WebShareJob? getWebShareJob(String fileId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeStorageRepository fakeRepo;

  setUp(() {
    fakeRepo = _FakeStorageRepository();
    ServiceLocator.instance.setStorageRepositoryForTesting(fakeRepo);
  });

  group('HomeCubit Local-First & Network Decoupling Tests', () {
    test('TC-01: refreshLocalData emits local Hive cache synchronously in Phase 1',
        () async {
      final cubit = HomeCubit();

      expect(cubit.state.recentFiles, isEmpty);
      expect(cubit.state.totalFiles, equals(0));

      await cubit.refreshLocalData();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.userName, equals('Test'));
      expect(cubit.state.userEmail, equals('test@example.com'));
      expect(cubit.state.recentFiles.length, equals(1));
      expect(cubit.state.recentFiles.first.name, equals('document.pdf'));
      expect(cubit.state.totalFiles, equals(42));
      expect(cubit.state.storageUsedMb, equals(150.5));
      expect(cubit.state.totalShares, equals(7));
      expect(cubit.state.totalDownloads, equals(12));

      // Assert ZERO network calls were dispatched during Phase 1
      expect(fakeRepo.getQuotaCallCount, equals(0));
      expect(fakeRepo.getMetadataCallCount, equals(0));

      await cubit.close();
    });

    test(
        'TC-02: enrichRemoteData acquires start-time lock and suppresses concurrent in-flight calls',
        () async {
      fakeRepo.quotaCompleter = Completer<Map<String, dynamic>>();
      fakeRepo.metadataCompleter = Completer<AppMetadata>();

      final cubit = HomeCubit();

      // Call #1: in-flight request started
      final future1 = cubit.enrichRemoteData(force: false);
      expect(fakeRepo.getQuotaCallCount, equals(1));
      expect(fakeRepo.getMetadataCallCount, equals(1));

      // Call #2: fast post-sync call arrives while Call #1 is still in-flight
      final future2 = cubit.enrichRemoteData(force: false);

      // Call #2 should be suppressed by the start-time lock
      expect(fakeRepo.getQuotaCallCount, equals(1));
      expect(fakeRepo.getMetadataCallCount, equals(1));

      // Resolve in-flight request
      fakeRepo.quotaCompleter!.complete({'used_bandwidth_bytes': 1024});
      fakeRepo.metadataCompleter!.complete(AppMetadata(
        owner: 'test_owner',
        storageUsedMb: 150.5,
        totalFiles: 42,
        metadataMessageId: 999,
        folders: [],
        categories: {},
        lastSynced: DateTime(2026, 1, 1),
      ));

      await future1;
      await future2;

      expect(cubit.state.webShareQuota, isNotNull);
      expect(cubit.state.metadata, isNotNull);

      await cubit.close();
    });

    test(
        'TC-03: sync(userInitiated: true) bypasses the 5-second cooldown and forces remote enrichment',
        () async {
      final cubit = HomeCubit();

      // First enrichment
      await cubit.enrichRemoteData(force: false);
      expect(fakeRepo.getQuotaCallCount, equals(1));
      expect(fakeRepo.getMetadataCallCount, equals(1));

      // Second unforced call within 5s is suppressed
      await cubit.enrichRemoteData(force: false);
      expect(fakeRepo.getQuotaCallCount, equals(1));
      expect(fakeRepo.getMetadataCallCount, equals(1));

      // Forced call (user pull-to-refresh) bypasses cooldown
      await cubit.enrichRemoteData(force: true);
      expect(fakeRepo.getQuotaCallCount, equals(2));
      expect(fakeRepo.getMetadataCallCount, equals(2));

      await cubit.close();
    });

    test(
        'TC-04: Debounced local refresh coalesces rapid events without network calls',
        () async {
      final cubit = HomeCubit();

      // Dispatch 50 rapid debounced local refresh triggers
      for (int i = 0; i < 50; i++) {
        cubit.scheduleDebouncedLocalRefreshForTesting();
      }

      // Wait for debounce timer to settle (350ms window)
      await Future<void>.delayed(const Duration(milliseconds: 450));

      expect(cubit.state.totalFiles, equals(42));
      expect(cubit.state.recentFiles.isNotEmpty, isTrue);

      // Local Hive debounce must NEVER dispatch remote network requests
      expect(fakeRepo.getQuotaCallCount, equals(0));
      expect(fakeRepo.getMetadataCallCount, equals(0));

      await cubit.close();
    });

    test(
        'TC-05: Disposed lifecycle safety - closing cubit before async resolution throws no exceptions',
        () async {
      fakeRepo.quotaCompleter = Completer<Map<String, dynamic>>();
      fakeRepo.metadataCompleter = Completer<AppMetadata>();

      final cubit = HomeCubit();

      // Start enrichment and close cubit while still in-flight
      final enrichFuture = cubit.enrichRemoteData(force: false);
      await cubit.close();

      expect(cubit.isClosed, isTrue);

      // Complete async operation post-close
      fakeRepo.quotaCompleter!.complete({'used_bandwidth_bytes': 1024});
      fakeRepo.metadataCompleter!.complete(AppMetadata(
        owner: 'test_owner',
        storageUsedMb: 150.5,
        totalFiles: 42,
        metadataMessageId: 999,
        folders: [],
        categories: {},
        lastSynced: DateTime(2026, 1, 1),
      ));

      // Should complete cleanly without throwing BadState: Cannot emit after close
      await expectLater(enrichFuture, completes);
    });

    test(
        'TC-06: enrichRemoteData deduplicates state emission when content is identical',
        () async {
      final cubit = HomeCubit();

      await cubit.enrichRemoteData(force: true);
      expect(cubit.state.metadata?.metadataMessageId, equals(999));

      int stateEmissions = 0;
      final sub = cubit.stream.listen((_) => stateEmissions++);

      // Second enrich with identical data
      await cubit.enrichRemoteData(force: true);

      // No new state should be emitted because content is unchanged
      expect(stateEmissions, equals(0));

      await sub.cancel();
      await cubit.close();
    });
  });
}
