/*
 * File: web_share_queue_service.dart
 * Description: Component and logic definition for web_share_queue_service.dart in TelStorage.
 */

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../constants/app_constants.dart';
import '../models/file_record.dart';
import '../models/folder_record.dart';
import '../models/web_share_job.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import '../utils/file_reader_stub.dart'
    if (dart.library.io) '../utils/file_reader_native.dart';
import 'download_service.dart';
import 'folder_traversal_service.dart';
import 'notification_service.dart';
import 'transfer_queue_service.dart';
import '../models/transfer_task.dart';
import 'web_share_api_client.dart';
import 'service_locator.dart';
import '../events/domain_event_bus.dart';
import 'web_share_settings_service.dart';
import 'zip_archive_service.dart';

class WebShareQueueService {
  final DownloadService _downloadService;
  final String _boxName;
  final WebShareApiClient _apiClient = WebShareApiClient();

  bool _isProcessing = false;

  WebShareQueueService(this._downloadService, this._boxName);

  Box get _box => Hive.box(_boxName);

  ValueListenable<Box> get listenable => _box.listenable();

  List<WebShareJob> get allShares {
    return _box.values
        .map((v) => WebShareJob.fromMap(Map<dynamic, dynamic>.from(v)))
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  /// Returns an existing completed and non-expired web share job for the given file, if one exists.
  WebShareJob? getActiveShare(String fileId) {
    final raw = _box.get(fileId);
    if (raw == null) return null;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(raw));
    if (!job.isComplete || job.shareUrl == null || job.shareUrl!.isEmpty) {
      return null;
    }

    if (job.expiryDays != null && job.completedAt != null) {
      final expiryDate = job.completedAt!.add(Duration(days: job.expiryDays!));
      if (DateTime.now().isAfter(expiryDate)) {
        return null;
      }
    }
    return job;
  }

  /// Enqueue a folder to be zipped and shared publicly on storage.to
  Future<void> enqueueFolderShare(FolderRecord folder,
      {String? password, int? maxDownloads, int? expiryDays, String? vanitySlug}) async {
    final cleanFolderName = FolderTraversalService.sanitizeSegment(folder.name);
    final zipName = '$cleanFolderName.zip';
    final allFolders = Hive.box<FolderRecord>(AppConstants.foldersBox).values.toList();
    final allFiles = Hive.box<FileRecord>(AppConstants.filesBox).values.toList();
    final items = FolderTraversalService.resolveDescendants(
      targetFolderId: folder.id,
      allFolders: allFolders,
      allFiles: allFiles,
    );
    final stats = FolderTraversalService.calculateStats(items);
    final syntheticFile = FileRecord(
      fileId: folder.id,
      name: zipName,
      mimeType: 'application/zip',
      sizeMb: stats.totalSizeMb,
      metadataMessageId: 0,
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: '',
    );
    await enqueueShare(
      syntheticFile,
      password: password,
      maxDownloads: maxDownloads,
      expiryDays: expiryDays,
      vanitySlug: vanitySlug,
    );
  }

  /// Enqueue a file to be shared publicly on storage.to
  Future<void> enqueueShare(FileRecord file,
      {String? password,
      int? maxDownloads,
      int? expiryDays,
      String? vanitySlug}) async {
    final existingMap = _box.get(file.fileId);
    if (existingMap != null) {
      final existingJob =
          WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));
      if (existingJob.isComplete) {
        AppLogger.i('Web share already completed for: ${file.name}',
            tag: 'WebShareQueue');
        if (password != null) {
          await setPassword(file.fileId, password);
        }
        if (maxDownloads != null) {
          await setMaxDownloads(file.fileId, maxDownloads);
        }
        if (expiryDays != null) {
          await setExpiry(file.fileId, expiryDays);
        }
        if (vanitySlug != null) {
          await setVanitySlug(file.fileId, vanitySlug);
        }
        return;
      }
      if (existingJob.status == 'queued' ||
          existingJob.status == 'downloading' ||
          existingJob.status == 'uploading') {
        final updated = existingJob.copyWith(
            password: password,
            maxDownloads: maxDownloads,
            expiryDays: expiryDays,
            vanitySlug: vanitySlug);
        await _box.put(file.fileId, updated.toMap());
        return;
      }
      final job = existingJob.copyWith(
        status: 'queued',
        progress: 0.0,
        error: null,
        password: password,
        maxDownloads: maxDownloads,
        expiryDays: expiryDays,
        vanitySlug: vanitySlug,
      );
      await _box.put(file.fileId, job.toMap());
    } else {
      final job = WebShareJob(
        fileId: file.fileId,
        name: file.name,
        mimeType: file.mimeType,
        sizeMb: file.sizeMb,
        progress: 0.0,
        status: 'queued',
        addedAt: DateTime.now(),
        password: password,
        maxDownloads: maxDownloads,
        expiryDays: expiryDays,
        vanitySlug: vanitySlug,
      );
      await _box.put(file.fileId, job.toMap());
    }

    TransferQueueService.instance.addTask(TransferTask(
      id: file.fileId,
      name: file.name,
      type: TransferType.share,
      sizeMb: file.sizeMb,
      addedAt: DateTime.now(),
      status: TransferStatus.pending,
      currentStage: 'Preparing share…',
    ));

    unawaited(_processQueue());
  }

  /// Restarts incomplete share jobs after a relaunch.
  Future<void> resumePendingShares() async {
    for (final job in allShares) {
      if (job.status == 'downloading' || job.status == 'uploading') {
        await _box.put(
          job.fileId,
          job
              .copyWith(status: 'queued', progress: 0.0, clearError: true)
              .toMap(),
        );
      }
    }
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        final shares = allShares;
        final nextJob = shares.cast<WebShareJob?>().firstWhere(
              (j) => j != null && j.status == 'queued',
              orElse: () => null,
            );

        if (nextJob == null) break;

        await _runJob(nextJob);
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _runJob(WebShareJob job) async {
    AppLogger.i('Starting share job for: ${job.name}', tag: 'WebShareQueue');
    WebShareJob current = job;

    try {
      if (!await Connectivity.hasConnection()) {
        throw Exception('No internet connection');
      }

      final visitorToken = await _apiClient.getOrCreateVisitorToken();
      File? tempZipToCleanup;
      Map<String, dynamic> uploadResult;

      // Check if job targets a folder
      final folderRecord =
          Hive.box<FolderRecord>(AppConstants.foldersBox).get(current.fileId);

      if (folderRecord != null) {
        // ── Folder Path: Package into ZIP and Stream to storage.to ───────
        final allFolders =
            Hive.box<FolderRecord>(AppConstants.foldersBox).values.toList();
        final allFiles =
            Hive.box<FileRecord>(AppConstants.filesBox).values.toList();
        final items = FolderTraversalService.resolveDescendants(
          targetFolderId: folderRecord.id,
          allFolders: allFolders,
          allFiles: allFiles,
        );

        if (items.isEmpty) {
          throw Exception('Folder contains no files to share');
        }

        current = current.copyWith(status: 'downloading', progress: 0.0);
        await _box.put(current.fileId, current.toMap());
        TransferQueueService.instance.updateTask(current.fileId,
            status: TransferStatus.downloading,
            progress: 0.0,
            currentStage: 'Preparing folder files…');

        try {
          final stagedZip = await ZipArchiveService.packageFolderToTempZip(
            folder: folderRecord,
            items: items,
            downloadService: _downloadService,
            transferId: current.fileId,
            onProgress: (p, stage) async {
              current = current.copyWith(progress: p * 0.40);
              await _box.put(current.fileId, current.toMap());
              TransferQueueService.instance.updateTask(
                current.fileId,
                progress: current.progress,
                currentStage: stage,
              );
            },
          );

          if (stagedZip == null) throw Exception('ZIP archive creation failed');
          tempZipToCleanup = stagedZip;

          current = current.copyWith(status: 'uploading', progress: 0.40);
          await _box.put(current.fileId, current.toMap());
          TransferQueueService.instance.updateTask(current.fileId,
              status: TransferStatus.sharing,
              progress: 0.40,
              currentStage: 'Uploading ZIP to Web…');

          uploadResult = await _apiClient.uploadFileToStorageTo(
            file: stagedZip,
            transferId: current.fileId,
            filename: current.name,
            mimeType: 'application/zip',
            visitorToken: visitorToken,
            onProgress: (pct) async {
              current = current.copyWith(progress: 0.40 + pct * 0.55);
              await _box.put(current.fileId, current.toMap());
              TransferQueueService.instance.updateTask(current.fileId,
                  progress: current.progress,
                  currentStage: 'Uploading… ${(pct * 100).toInt()}%');
            },
          );
        } finally {
          if (tempZipToCleanup != null &&
              tempZipToCleanup.parent.existsSync()) {
            try {
              await tempZipToCleanup.parent.delete(recursive: true);
            } catch (_) {}
          }
        }
      } else {
        // ── Single File Path: Download and Upload ─────────────────────────
        current = current.copyWith(status: 'downloading', progress: 0.0);
        await _box.put(current.fileId, current.toMap());
        TransferQueueService.instance.updateTask(current.fileId,
            status: TransferStatus.downloading,
            progress: 0.0,
            currentStage: 'Downloading from Cloud…');

        final fileRecord = FileRecord(
          fileId: current.fileId,
          name: current.name,
          mimeType: current.mimeType,
          sizeMb: current.sizeMb,
          metadataMessageId: 0,
          uploadedAt: DateTime.now(),
          chunkCount: 1,
          sha256Hash: '',
        );

        final localCachedFile =
            Hive.box<FileRecord>(AppConstants.filesBox).get(current.fileId);
        if (localCachedFile != null) {
          fileRecord.metadataFileId = localCachedFile.metadataFileId;
          fileRecord.metadataMessageId = localCachedFile.metadataMessageId;
        }

        final bytes = await _downloadService.downloadFile(
          fileRecord,
          (progress, status) async {
            current = current.copyWith(progress: progress * 0.40);
            await _box.put(current.fileId, current.toMap());
            TransferQueueService.instance.updateTask(current.fileId,
                progress: current.progress,
                currentStage: 'Downloading… ${(progress * 100).toInt()}%');
          },
        );

        current = current.copyWith(status: 'uploading', progress: 0.40);
        await _box.put(current.fileId, current.toMap());
        TransferQueueService.instance.updateTask(current.fileId,
            status: TransferStatus.sharing,
            progress: 0.40,
            currentStage: 'Uploading to Web…');

        uploadResult = await _apiClient.uploadToStorageTo(
          bytes: bytes,
          transferId: current.fileId,
          filename: current.name,
          mimeType: current.mimeType,
          visitorToken: visitorToken,
          onProgress: (pct) async {
            current = current.copyWith(progress: 0.40 + pct * 0.55);
            await _box.put(current.fileId, current.toMap());
            TransferQueueService.instance.updateTask(current.fileId,
                progress: current.progress,
                currentStage: 'Uploading… ${(pct * 100).toInt()}%');
          },
        );
      }

      // ── Step 3: Save Share Record ─────────────────────────────────────────
      current = current.copyWith(
        status: 'completed',
        progress: 1.0,
        shareUrl: uploadResult['share_url'] as String,
        ownerToken: uploadResult['owner_token'] as String,
        storageToId: uploadResult['id'] as String,
        completedAt: DateTime.now(),
      );
      await _box.put(current.fileId, current.toMap());
      TransferQueueService.instance.updateTask(current.fileId,
          status: TransferStatus.completed,
          progress: 1.0,
          currentStage: 'Share Link Ready!');

      await NotificationService.instance.showCompletionNotification(
        title: 'Share Link Ready',
        body: 'Link for ${current.name} is ready to copy.',
        payload: 'transfer_share',
        actions: [
          if (current.shareUrl != null)
            AndroidNotificationAction(
              'copy_url:${current.shareUrl}',
              'Copy Link',
              showsUserInterface: true,
            ),
          const AndroidNotificationAction(
            'view_shared',
            'View Shares',
            showsUserInterface: true,
          ),
        ],
      );

      // ── Step 4: Upload Thumbnail ──────────────────────────────────────────
      final cachedFile =
          Hive.box<FileRecord>(AppConstants.filesBox).get(current.fileId);
      if (cachedFile?.thumbnailFileId != null) {
        try {
          final thumbData = await ServiceLocator.instance.thumbnailRepository
              .getThumbnailData(cachedFile!);
          if (thumbData != null) {
            Uint8List? thumbBytes;
            if (thumbData is Uint8List) {
              thumbBytes = thumbData;
            } else if (thumbData is String) {
              thumbBytes = await readFileBytes(thumbData);
            }

            if (thumbBytes != null) {
              await _apiClient.uploadThumbnailRemote(
                  current.storageToId!, current.ownerToken!, thumbBytes);
            }
          }
        } catch (e) {
          AppLogger.w('Failed to upload web thumbnail: $e',
              tag: 'WebShareQueue');
        }
      }

      // ── Step 5: Apply Security & Vanity Settings ─────────────────────────
      if (current.password != null) {
        try { await setPassword(current.fileId, current.password!); } catch (_) {}
      }
      if (current.maxDownloads != null) {
        try { await setMaxDownloads(current.fileId, current.maxDownloads!); } catch (_) {}
      }
      if (current.expiryDays != null) {
        try { await setExpiry(current.fileId, current.expiryDays!); } catch (_) {}
      }
      if (current.vanitySlug != null && current.vanitySlug!.isNotEmpty) {
        try { await setVanitySlug(current.fileId, current.vanitySlug!); } catch (_) {}
      }

      DomainEventBus.instance.fire(
        WebShareCompletedEvent(current.fileId, current.shareUrl ?? ''),
      );

      AppLogger.i('Web share completed successfully for: ${current.name}',
          tag: 'WebShareQueue');
    } catch (e) {
      final wasCancelled =
          TransferQueueService.instance.isCancelled(current.fileId);
      AppLogger.e(
          'Web share ${wasCancelled ? 'cancelled' : 'failed'} for ${current.name}: $e',
          tag: 'WebShareQueue');
      current = current.copyWith(
        status: wasCancelled ? 'cancelled' : 'failed',
        error: wasCancelled ? null : e.toString(),
      );
      await _box.put(current.fileId, current.toMap());
      TransferQueueService.instance.updateTask(
        current.fileId,
        status: wasCancelled ? TransferStatus.cancelled : TransferStatus.failed,
        error: wasCancelled ? null : e.toString(),
      );
      if (!wasCancelled) {
        await NotificationService.instance.showCompletionNotification(
          title: 'Share Failed',
          body: 'Failed to share ${current.name}',
          bigText: 'Failed to share ${current.name}\n\nError: $e',
          payload: 'transfer_share',
        );
      }
    }
  }

  late final WebShareSettingsService _settings =
      WebShareSettingsService(apiClient: _apiClient, box: _box);

  Future<void> deleteShare(String fileId) => _settings.deleteShare(fileId);
  Future<void> setPassword(String fileId, String password) =>
      _settings.setPassword(fileId, password);
  Future<void> setExpiry(String fileId, int days) =>
      _settings.setExpiry(fileId, days);
  Future<void> setMaxDownloads(String fileId, int? maxDownloads) =>
      _settings.setMaxDownloads(fileId, maxDownloads);
  Future<void> setVanitySlug(String fileId, String vanitySlug) =>
      _settings.setVanitySlug(fileId, vanitySlug);

  Future<Map<String, dynamic>> getBandwidthStatus() async {
    final visitorToken = await _apiClient.getOrCreateVisitorToken();
    return _apiClient.getBandwidthStatusRemote(visitorToken);
  }

  Future<bool> isFilePending(String storageToId) async {
    return _apiClient.isFilePendingRemote(storageToId);
  }
}
