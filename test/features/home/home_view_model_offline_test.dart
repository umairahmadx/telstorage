/*
 * File: home_view_model_offline_test.dart
 * Description: Unit tests validating HomeCubit preflight offline checks and graceful connection error fallback.
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/app_metadata.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/sync_service.dart';
import 'package:telstorage/core/utils/connectivity.dart';
import 'package:telstorage/features/home/presentation/screens/home/viewmodel/home_view_model.dart';
import 'package:telstorage/features/storage/data/repositories/storage_repository.dart';

class _FakeStorageRepository extends Fake implements StorageRepository {
  @override
  Future<String?> getUserEmail() async => 'user@example.com';

  @override
  List<FileRecord> getRecentFiles(int limit) => [];

  @override
  int getTotalFiles() => 0;

  @override
  double getTotalSizeMb() => 0.0;

  @override
  int getTotalShares() => 0;

  @override
  int getTotalCompletedDownloads() => 0;

  @override
  Future<AppMetadata> getAppMetadata() async => AppMetadata(
        owner: 'test',
        storageUsedMb: 0,
        totalFiles: 0,
        metadataMessageId: 0,
        folders: [],
        categories: {},
        lastSynced: DateTime(2026, 1, 1),
      );
}

class _FakeFailingSyncService extends Fake implements SyncService {
  int syncCallCount = 0;

  @override
  Future<SyncResult> syncFromTelegram({
    void Function(double progress, String status)? onProgress,
    bool autoCleanOrphans = true,
  }) async {
    syncCallCount++;
    throw const SocketException("Failed host lookup: 'api.telegram.org'");
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeStorageRepository fakeRepo;
  late _FakeFailingSyncService fakeSyncService;

  setUp(() {
    fakeRepo = _FakeStorageRepository();
    fakeSyncService = _FakeFailingSyncService();
    ServiceLocator.instance.setStorageRepositoryForTesting(fakeRepo);
    ServiceLocator.instance.setSyncServiceForTesting(fakeSyncService);
    Connectivity.mockConnectionStatus = null;
  });

  tearDown(() {
    Connectivity.mockConnectionStatus = null;
  });

  group('HomeCubit Offline Resilience Tests', () {
    test('TC-HOME-OFFLINE-01: When device is offline, sync() skips remote network calls and sets offline status without error', () async {
      Connectivity.mockConnectionStatus = false;
      final cubit = HomeCubit();

      await cubit.sync();

      expect(fakeSyncService.syncCallCount, equals(0));
      expect(cubit.state.isSyncing, isFalse);
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.syncStatus, equals('Offline — Changes Queued'));

      await cubit.close();
    });

    test('TC-HOME-OFFLINE-02: When Telegram fails host lookup during sync, cubit catches connection error gracefully', () async {
      Connectivity.mockConnectionStatus = true;
      final cubit = HomeCubit();

      await cubit.sync();

      expect(fakeSyncService.syncCallCount, equals(1));
      expect(cubit.state.isSyncing, isFalse);
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.syncStatus, equals('Offline — Changes Queued'));

      await cubit.close();
    });
  });
}
