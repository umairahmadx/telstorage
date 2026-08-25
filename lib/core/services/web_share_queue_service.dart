/*
 * File: web_share_queue_service.dart
 * Description: Component and logic definition for web_share_queue_service.dart in TelStorage.
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../constants/app_constants.dart';
import '../models/file_record.dart';
import '../models/web_share_job.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import '../utils/file_reader_stub.dart'
    if (dart.library.io) '../utils/file_reader_native.dart';
import 'download_service.dart';
import 'notification_service.dart';
import 'transfer_queue_service.dart';
import '../models/transfer_task.dart';
import 'web_share_api_client.dart';
import 'service_locator.dart';
import '../events/domain_event_bus.dart';

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

  /// Enqueue a file to be shared publicly on storage.to
  Future<void> enqueueShare(FileRecord file,
      {String? password, int? maxDownloads, int? expiryDays, String? vanitySlug}) async {
    final existingMap = _box.get(file.fileId);
    if (existingMap != null) {
      final existingJob =
          WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));
      if (existingJob.isComplete) {
        AppLogger.i('Web share already completed for: ${file.name}',
            tag: 'WebShareQueue');
        if (password != null) await setPassword(file.fileId, password);
        if (maxDownloads != null) await setMaxDownloads(file.fileId, maxDownloads);
        if (expiryDays != null) await setExpiry(file.fileId, expiryDays);
        if (vanitySlug != null) await setVanitySlug(file.fileId, vanitySlug);
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
          job.copyWith(status: 'queued', progress: 0.0, clearError: true).toMap(),
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

      // ── Step 1: Download file from Telegram ──────────────────────────────
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

      // ── Step 2: Upload to storage.to R2 ──────────────────────────────────
      current = current.copyWith(status: 'uploading', progress: 0.40);
      await _box.put(current.fileId, current.toMap());
      TransferQueueService.instance.updateTask(current.fileId,
          status: TransferStatus.sharing,
          progress: 0.40,
          currentStage: 'Uploading to Web…');

      final uploadResult = await _apiClient.uploadToStorageTo(
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
            AndroidNotificationAction('copy_${current.fileId}', 'Copy Link'),
        ],
      );

      // ── Step 4: Upload Thumbnail ──────────────────────────────────────────
      if (localCachedFile?.thumbnailFileId != null) {
        try {
          final thumbData = await ServiceLocator.instance.thumbnailRepository
              .getThumbnailData(localCachedFile!);
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
          AppLogger.w('Failed to upload web thumbnail: $e', tag: 'WebShareQueue');
        }
      }

      // ── Step 5: Apply Security & Vanity Settings ─────────────────────────
      if (current.password != null) {
        try {
          await setPassword(current.fileId, current.password!);
        } catch (_) {}
      }
      if (current.maxDownloads != null) {
        try {
          await setMaxDownloads(current.fileId, current.maxDownloads!);
        } catch (_) {}
      }
      if (current.expiryDays != null) {
        try {
          await setExpiry(current.fileId, current.expiryDays!);
        } catch (_) {}
      }
      if (current.vanitySlug != null && current.vanitySlug!.isNotEmpty) {
        try {
          await setVanitySlug(current.fileId, current.vanitySlug!);
        } catch (_) {}
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
          body: 'Failed to share ${current.name}: $e',
        );
      }
    }
  }

  Future<void> deleteShare(String fileId) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId != null && job.ownerToken != null) {
      try {
        await _apiClient.deleteShareRemote(job.storageToId!, job.ownerToken!);
      } catch (e) {
        AppLogger.w('Failed deleteShare: $e', tag: 'WebShareQueue');
      }
    }
    await _box.delete(fileId);
  }

  Future<void> setPassword(String fileId, String password) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final success = await _apiClient.setPasswordRemote(
        job.storageToId!, job.ownerToken!, password);
    if (success) {
      await _box.put(fileId, job.copyWith(password: password).toMap());
    } else {
      throw Exception('Failed password update');
    }
  }

  Future<void> setExpiry(String fileId, int days) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final success = await _apiClient.setExpiryRemote(
        job.storageToId!, job.ownerToken!, days);
    if (success) {
      await _box.put(fileId, job.copyWith(expiryDays: days).toMap());
    } else {
      throw Exception('Failed expiry update');
    }
  }

  Future<void> setMaxDownloads(String fileId, int? maxDownloads) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final success = await _apiClient.setMaxDownloadsRemote(
        job.storageToId!, job.ownerToken!, maxDownloads);
    if (success) {
      await _box.put(fileId, job.copyWith(maxDownloads: maxDownloads).toMap());
    } else {
      throw Exception('Failed download cap update');
    }
  }

  Future<void> setVanitySlug(String fileId, String vanitySlug) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final formattedSlug = vanitySlug.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\-]'), '-');
    final success = await _apiClient.setVanitySlugRemote(
        job.storageToId!, job.ownerToken!, formattedSlug);
    if (success) {
      final updatedUrl = 'https://storage.to/v/$formattedSlug';
      await _box.put(
        fileId,
        job.copyWith(shareUrl: updatedUrl, vanitySlug: formattedSlug).toMap(),
      );
    } else {
      throw Exception('Failed vanity slug update');
    }
  }

  Future<Map<String, dynamic>> getBandwidthStatus() async {
    final visitorToken = await _apiClient.getOrCreateVisitorToken();
    return _apiClient.getBandwidthStatusRemote(visitorToken);
  }

  Future<bool> isFilePending(String storageToId) async {
    return _apiClient.isFilePendingRemote(storageToId);
  }
}
