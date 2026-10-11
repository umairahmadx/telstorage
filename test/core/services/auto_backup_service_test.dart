/*
 * File: auto_backup_service_test.dart
 * Description: Unit tests for AutoBackupService scan-diff, eligibility,
 * backup path setup, watermark advance, retention, and free-space guard.
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/models/backup_ledger_entry.dart';
import 'package:telstorage/core/models/backup_rule.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/models/folder_record.dart';
import 'package:telstorage/core/services/auto_backup_engine.dart';
import 'package:telstorage/core/services/auto_backup_service.dart';
import 'package:telstorage/core/services/file_manager.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/metadata_service.dart';
import 'package:telstorage/core/services/telegram_service.dart';
import 'package:telstorage/shared/widgets/device_file_picker/device_media_scanner.dart';

/// Fake AssetEntity exposing only the metadata the service reads.
class _FakeAsset extends AssetEntity {
  /// Constructs _FakeAsset.
  _FakeAsset({
    required super.id,
    super.title,
    super.modifiedDateSecond,
    super.typeInt = 1,
    int? fileSize,
    this.throwSize = false,
  })  : _fileSize = fileSize,
        super(width: 10, height: 10);

  /// Whether size reads throw (unresolvable asset path).
  final bool throwSize;
  final int? _fileSize;

  /// Asset kind reported to the service.
  @override
  AssetType get type => AssetType.image;

  @override
  Future<int> get fileSize async {
    if (throwSize) throw StateError('unreadable');
    return _fileSize ?? 1024;
  }
}

/// Recording FileManager double for folder/retention side effects.
class _RecordingFileManager extends FileManagerService {
  /// Constructs _RecordingFileManager.
  _RecordingFileManager(
    super.meta,
    super.telegram,
    super.hive,
  );

  /// Folder names created, in order.
  final List<String> createdFolders = [];

  /// Parent ids passed to createFolder, keyed by folder name.
  final Map<String, String?> createdParents = {};

  /// File ids deleted, in order.
  final List<String> deletedFiles = [];

  @override
  Future<void> createFolder(String name,
      {String? parentId, String? folderId}) async {
    createdFolders.add(name);
    createdParents[name] = parentId;
    await HiveService.instance.saveFolder(FolderRecord(
      id: folderId ?? 'id-$name-${createdFolders.length}',
      name: name,
      parentId: parentId,
      createdAt: DateTime(2025, 1, 1),
    ));
  }

  @override
  Future<void> deleteFile(String fileId) async {
    deletedFiles.add(fileId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<BackupLedgerEntry> ledgerBox;

  BackupRule cameraRule() => BackupRule(
        id: 'camera',
        albumName: 'Camera',
        enabled: true,
        backfillDone: true,
        createdAt: DateTime(2025, 6, 1),
        windowStartMinutes: 0,
        windowEndMinutes: 1439,
      );

  MediaAlbum cameraAlbum() => const MediaAlbum(
        id: 'album-camera',
        name: 'Camera',
        mediaCount: 2,
        pathEntity: null,
      );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('backup_service_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(FileRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(FolderRecordAdapter());
    }
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(BackupRuleAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(BackupLedgerEntryAdapter());
    }
    await Hive.openBox<FileRecord>(AppConstants.filesBox);
    await Hive.openBox<FolderRecord>(AppConstants.foldersBox);
    await Hive.openBox<int>(AppConstants.partitionSyncBox);
    ledgerBox = await Hive.openBox<BackupLedgerEntry>(
      AppConstants.backupLedgerBox,
    );
    await ledgerBox.clear();
  });

  tearDown(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('isEligibleNow', () {
    test('disabled rule is not eligible', () async {
      final service = AutoBackupService(ledgerBox: ledgerBox);
      final rule = cameraRule()..enabled = false;
      final result = await service.isEligibleNow(rule);
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.reason, BackupBlockReason.disabled);
    });

    test('window, metered, and charging gates apply in order', () async {
      final service = AutoBackupService(
        ledgerBox: ledgerBox,
        isUnmetered: () async => false,
        isCharging: () async => false,
      );
      final rule = cameraRule()
        ..windowStartMinutes = 120
        ..windowEndMinutes = 300;
      final outside = await service.isEligibleNow(
        rule,
        now: DateTime(2026, 1, 1, 12, 0),
      );
      expect(outside.dataOrNull!.reason, BackupBlockReason.outsideWindow);

      rule
        ..windowStartMinutes = 0
        ..windowEndMinutes = 1439;
      final metered = await service.isEligibleNow(
        rule,
        now: DateTime(2026, 1, 1, 3, 0),
      );
      expect(metered.dataOrNull!.reason, BackupBlockReason.metered);

      rule.wifiOnly = false;
      rule.chargingOnly = true;
      final charger = await service.isEligibleNow(
        rule,
        now: DateTime(2026, 1, 1, 3, 0),
      );
      expect(charger.dataOrNull!.reason, BackupBlockReason.notCharging);

      rule.chargingOnly = false;
      final ready = await service.isEligibleNow(
        rule,
        now: DateTime(2026, 1, 1, 3, 0),
      );
      expect(ready.dataOrNull!.isEligible, isTrue);
    });
  });

  group('collectDueAssets', () {
    test('permission denial yields a failure, never a crash', () async {
      final service = AutoBackupService(
        ledgerBox: ledgerBox,
        requestPermission: () async => false,
      );
      final result = await service.collectDueAssets(cameraRule());
      expect(result.isFailure, isTrue);
    });

    test('new assets are due; known fingerprints are skipped', () async {
      final known = _FakeAsset(
        id: 'a1',
        title: 'IMG_001.jpg',
        modifiedDateSecond: 1749000000,
        fileSize: 1024,
      );
      final fresh = _FakeAsset(
        id: 'a2',
        title: 'IMG_002.jpg',
        modifiedDateSecond: 1749100000,
        fileSize: 2048,
      );
      final service = AutoBackupService(
        ledgerBox: ledgerBox,
        requestPermission: () async => true,
        loadAlbums: () async => [cameraAlbum()],
        loadPage: (album, page, pageSize) async =>
            page == 0 ? [known, fresh] : [],
      );
      const knownDto = BackupAsset(
        assetId: 'a1',
        title: 'IMG_001.jpg',
        modifiedMs: 1749000000000,
        sizeBytes: 1024,
        isVideo: false,
      );
      await ledgerBox.put(
        'a1',
        BackupLedgerEntry(
          assetId: 'a1',
          fingerprint: knownDto.fingerprint,
          destFileId: 'cloud-a1',
          uploadedAt: DateTime(2025, 7, 1),
        ),
      );
      final result = await service.collectDueAssets(cameraRule());
      expect(result.isSuccess, isTrue);
      final collected = result.dataOrNull!;
      expect(collected.uploads.map((u) => u.asset.assetId), ['a2']);
      expect(collected.plan.skippedKnown, 1);
    });

    test('unreadable size counts as skippedUnresolvable', () async {
      final broken = _FakeAsset(
        id: 'bad',
        title: 'IMG_BAD.jpg',
        modifiedDateSecond: 1749000000,
        throwSize: true,
      );
      final service = AutoBackupService(
        ledgerBox: ledgerBox,
        requestPermission: () async => true,
        loadAlbums: () async => [cameraAlbum()],
        loadPage: (album, page, pageSize) async =>
            page == 0 ? [broken] : [],
      );
      final result = await service.collectDueAssets(cameraRule());
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.skippedUnresolvable, 1);
      expect(result.dataOrNull!.uploads, isEmpty);
    });
  });

  group('ensureBackupPath', () {
    test('adopts existing Backup folder and creates album child', () async {
      final telegram = TelegramService();
      final meta = MetadataService(telegram);
      final files = _RecordingFileManager(
        meta,
        telegram,
        HiveService.instance,
      );
      await HiveService.instance.saveFolder(FolderRecord(
        id: 'backup-root',
        name: 'Backup',
        createdAt: DateTime(2025, 1, 1),
      ));
      final service = AutoBackupService(
        ledgerBox: ledgerBox,
        fileManager: files,
      );
      final rule = cameraRule();
      final result = await service.ensureBackupPath(
        'Camera',
        rule: rule,
      );
      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull!.backupFolderId, 'backup-root');
      expect(files.createdFolders, ['Camera']);
      expect(files.createdParents['Camera'], 'backup-root');
      expect(rule.backupFolderId, 'backup-root');
      expect(rule.albumFolderId, isNotNull);
    });
  });

  group('advanceWatermark + retention + free space', () {
    test('watermark records only completed uploads', () async {
      final service = AutoBackupService(ledgerBox: ledgerBox);
      final rule = cameraRule();
      const asset = BackupAsset(
        assetId: 'done-1',
        title: 'IMG_DONE.jpg',
        modifiedMs: 1749000000000,
        sizeBytes: 1024,
        isVideo: false,
      );
      const skipped = BackupAsset(
        assetId: 'todo-1',
        title: 'IMG_TODO.jpg',
        modifiedMs: 1749000000000,
        sizeBytes: 1024,
        isVideo: false,
      );
      final uploads = [
        const BackupUploadItem(asset: asset, destinationName: 'IMG_DONE.jpg'),
        const BackupUploadItem(asset: skipped, destinationName: 'IMG_TODO.jpg'),
      ];
      final result = await service.advanceWatermark(
        rule: rule,
        uploads: uploads,
        destFileIdsByAssetId: {'done-1': 'cloud-done-1'},
        destFolderId: 'album-folder',
        deleteReplaced: false,
      );
      expect(result.isSuccess, isTrue);
      expect(ledgerBox.get('done-1')!.destFileId, 'cloud-done-1');
      expect(ledgerBox.get('todo-1'), isNull);
      expect(rule.lastUploadedCount, 1);
    });

    test('free-space guard skips below twice the largest file', () async {
      final tight = AutoBackupService(
        ledgerBox: ledgerBox,
        freeSpaceBytes: () async => 100,
      );
      const asset = BackupAsset(
        assetId: 'big',
        title: 'MOV_BIG.mp4',
        modifiedMs: 1749000000000,
        sizeBytes: 1024,
        isVideo: true,
      );
      final blocked = await tight.ensureFreeSpaceFor([asset]);
      expect(blocked.isFailure, isTrue);

      final unknown = AutoBackupService(
        ledgerBox: ledgerBox,
        freeSpaceBytes: () async => null,
      );
      final allowed = await unknown.ensureFreeSpaceFor([asset]);
      expect(allowed.isSuccess, isTrue);
    });
  });
}
