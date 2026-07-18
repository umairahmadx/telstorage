import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

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

import 'service_locator.dart';

class WebShareQueueService {
  static const _r2MinimumTransferTimeout = Duration(minutes: 5);
  static const _r2MaximumTransferTimeout = Duration(minutes: 45);
  static const _assumedMinimumUploadSpeedBytesPerSecond = 64 * 1024;

  final DownloadService _downloadService;
  final String _boxName;
  final _dio = Dio(BaseOptions(
    baseUrl: 'https://storage.to/api',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  bool _isProcessing = false;

  WebShareQueueService(this._downloadService, this._boxName);

  Box get _box => Hive.box(_boxName);

  ValueListenable<Box> get listenable => _box.listenable();

  /// Allows slow connections to finish a signed R2 upload without leaving a
  /// stalled request open indefinitely. Each multipart part gets its own
  /// timeout, calculated from its actual size.
  Duration _r2TransferTimeout(int byteLength) {
    final estimatedSeconds =
        (byteLength / _assumedMinimumUploadSpeedBytesPerSecond).ceil();
    final bufferedSeconds = estimatedSeconds * 2;
    final timeoutSeconds =
        _r2MinimumTransferTimeout.inSeconds + bufferedSeconds;

    return Duration(
      seconds: timeoutSeconds
          .clamp(
            _r2MinimumTransferTimeout.inSeconds,
            _r2MaximumTransferTimeout.inSeconds,
          )
          .toInt(),
    );
  }

  List<WebShareJob> get allShares {
    return _box.values
        .map((v) => WebShareJob.fromMap(Map<dynamic, dynamic>.from(v)))
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  /// Unique anonymous client visitor token.
  Future<String> _getOrCreateVisitorToken() async {
    const storage = FlutterSecureStorage();
    String? token = await storage.read(key: 'visitor_token');
    if (token == null) {
      token =
          'visitor_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
      await storage.write(key: 'visitor_token', value: token);
    }
    return token;
  }

  /// Enqueue a file to be shared publicly on storage.to
  Future<void> enqueueShare(FileRecord file,
      {String? password, int? maxDownloads, int? expiryDays}) async {
    final existingMap = _box.get(file.fileId);
    if (existingMap != null) {
      final existingJob =
          WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));
      if (existingJob.isComplete) {
        AppLogger.i('Web share already completed for: ${file.name}',
            tag: 'WebShareQueue');
        // If completed, we can still update settings immediately
        if (password != null) {
          await setPassword(file.fileId, password);
        }
        if (maxDownloads != null) {
          await setMaxDownloads(file.fileId, maxDownloads);
        }
        if (expiryDays != null) {
          await setExpiry(file.fileId, expiryDays);
        }
        return;
      }
      if (existingJob.status == 'queued' ||
          existingJob.status == 'downloading' ||
          existingJob.status == 'uploading') {
        // Update intended settings even if already in queue
        final updated = existingJob.copyWith(
            password: password,
            maxDownloads: maxDownloads,
            expiryDays: expiryDays);
        await _box.put(file.fileId, updated.toMap());
        return;
      }
      // Retry/resume failed job
      final job = existingJob.copyWith(
        status: 'queued',
        progress: 0.0,
        error: null,
        password: password,
        maxDownloads: maxDownloads,
        expiryDays: expiryDays,
      );
      await _box.put(file.fileId, job.toMap());
    } else {
      // Create new job
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
      );
      await _box.put(file.fileId, job.toMap());
    }

    // Add to unified transfer queue
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

  /// Restarts incomplete share jobs after a relaunch. Their temporary download
  /// bytes are not persisted, so jobs that were in progress restart safely from
  /// the queued state.
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

  /// Processes the queue sequentially (max 1 concurrent upload)
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

      final visitorToken = await _getOrCreateVisitorToken();

      // ── Step 1: Download the file from Telegram (0% - 40%) ────────────────
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

      // Find the metadata file id from local cache to locate file chunks
      final localCachedFile =
          Hive.box<FileRecord>(AppConstants.filesBox).get(current.fileId);
      if (localCachedFile != null) {
        fileRecord.metadataFileId = localCachedFile.metadataFileId;
        fileRecord.metadataMessageId = localCachedFile.metadataMessageId;
      }

      final bytes = await _downloadService.downloadFile(
        fileRecord,
        (progress, status) async {
          current = current.copyWith(
            progress: progress * 0.40,
          );
          await _box.put(current.fileId, current.toMap());
          TransferQueueService.instance.updateTask(current.fileId,
              progress: current.progress,
              currentStage: 'Downloading… ${(progress * 100).toInt()}%');
        },
      );

      // ── Step 2: Upload to storage.to (40% - 95%) ───────────────────────────
      current = current.copyWith(status: 'uploading', progress: 0.40);
      await _box.put(current.fileId, current.toMap());
      TransferQueueService.instance.updateTask(current.fileId,
          status: TransferStatus.sharing,
          progress: 0.40,
          currentStage: 'Uploading to Web…');

      final uploadResult = await _uploadToStorageTo(
        bytes: bytes,
        transferId: current.fileId,
        filename: current.name,
        mimeType: current.mimeType,
        visitorToken: visitorToken,
        onProgress: (pct) async {
          current = current.copyWith(
            progress: 0.40 + pct * 0.55,
          );
          await _box.put(current.fileId, current.toMap());
          TransferQueueService.instance.updateTask(current.fileId,
              progress: current.progress,
              currentStage: 'Uploading… ${(pct * 100).toInt()}%');
        },
      );

      // ── Step 3: Complete & Save Share Record (100%) ────────────────────────
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

      // ── Step 4: Upload Thumbnail (if available) ───────────────────────────
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
              await uploadThumbnail(
                  current.storageToId!, current.ownerToken!, thumbBytes);
            }
          }
        } catch (e) {
          AppLogger.w('Failed to upload web thumbnail: $e',
              tag: 'WebShareQueue');
        }
      }

      // ── Step 5: Apply initial security settings (password/limits/expiry) ──
      if (current.password != null) {
        try {
          await setPassword(current.fileId, current.password!);
        } catch (e) {
          AppLogger.w('Failed to apply initial password to share: $e',
              tag: 'WebShareQueue');
        }
      }
      if (current.maxDownloads != null) {
        try {
          await setMaxDownloads(current.fileId, current.maxDownloads!);
        } catch (e) {
          AppLogger.w('Failed to apply initial download cap to share: $e',
              tag: 'WebShareQueue');
        }
      }
      if (current.expiryDays != null) {
        try {
          await setExpiry(current.fileId, current.expiryDays!);
        } catch (e) {
          AppLogger.w('Failed to apply initial expiry to share: $e',
              tag: 'WebShareQueue');
        }
      }

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

  /// Internal helper to perform storage.to upload dance
  Future<Map<String, dynamic>> _uploadToStorageTo({
    required Uint8List bytes,
    required String transferId,
    required String filename,
    required String mimeType,
    required String visitorToken,
    required void Function(double pct) onProgress,
  }) async {
    if (TransferQueueService.instance.isCancelled(transferId)) {
      throw Exception('Share cancelled by user');
    }
    // 1. Init upload
    final initRes = await _dio.post(
      '/upload/init',
      data: {
        'filename': filename,
        'content_type': mimeType,
        'size': bytes.length,
      },
      options: Options(
        headers: {
          'X-Visitor-Token': visitorToken,
          'Content-Type': 'application/json',
        },
      ),
    );

    if (initRes.data['success'] != true) {
      throw Exception(initRes.data['error'] ?? 'Upload initialization failed');
    }

    final type = initRes.data['type'] as String? ?? 'single';
    final r2Key = initRes.data['r2_key'] as String;
    String finalOwnerToken = initRes.data['owner_token'] as String? ?? '';

    if (type == 'single') {
      final uploadUrl = initRes.data['upload_url'] as String;
      await _dio.put(
        uploadUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(
          sendTimeout: _r2TransferTimeout(bytes.length),
          receiveTimeout: _r2TransferTimeout(bytes.length),
          headers: {
            Headers.contentLengthHeader: bytes.length,
            Headers.contentTypeHeader: mimeType,
          },
        ),
        onSendProgress: (sent, total) {
          final pct = total > 0 ? sent / total : 0.0;
          onProgress(pct);
        },
      );
    } else {
      // Multipart upload (> 50 MB)
      final uploadId = initRes.data['upload_id'] as String;
      final partSize = initRes.data['part_size'] as int;
      final totalParts = initRes.data['total_parts'] as int;
      final initialUrls = initRes.data['initial_urls'] as Map<String, dynamic>;

      final List<Map<String, dynamic>> completedParts = [];

      for (var i = 0; i < totalParts; i++) {
        while (TransferQueueService.instance.isPaused(transferId)) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (TransferQueueService.instance.isCancelled(transferId)) {
          throw Exception('Share cancelled by user');
        }
        final partNumber = i + 1;
        final start = i * partSize;
        final end = (start + partSize).clamp(0, bytes.length);
        final partBytes = bytes.sublist(start, end);

        String partUrl = initialUrls[partNumber.toString()] as String? ?? '';
        if (partUrl.isEmpty) {
          final partUrlRes = await _dio.post(
            '/upload/parts',
            data: {
              'upload_id': uploadId,
              'part_numbers': [partNumber]
            },
            options:
                Options(headers: {'Authorization': 'Owner $finalOwnerToken'}),
          );
          if (partUrlRes.data['success'] == true) {
            final partUrls = partUrlRes.data['part_urls'] as List;
            if (partUrls.isNotEmpty) partUrl = partUrls.first['url'] as String;
          }
        }

        if (partUrl.isEmpty) throw Exception('Failed to get part URL');

        final res = await _dio.put(
          partUrl,
          data: Stream.fromIterable([partBytes]),
          options: Options(
            sendTimeout: _r2TransferTimeout(partBytes.length),
            receiveTimeout: _r2TransferTimeout(partBytes.length),
            headers: {
              Headers.contentLengthHeader: partBytes.length,
              Headers.contentTypeHeader: mimeType,
            },
          ),
          onSendProgress: (sent, total) {
            final partPct = total > 0 ? sent / total : 0.0;
            onProgress((i + partPct) / totalParts);
          },
        );

        final etag =
            res.headers.value('etag') ?? res.headers.value('ETag') ?? '';
        if (etag.isEmpty) throw Exception('No ETag');
        completedParts.add({'partNumber': partNumber, 'etag': etag});
      }

      await _dio.post(
        '/upload/complete-multipart',
        data: {'upload_id': uploadId, 'parts': completedParts},
        options: Options(headers: {
          'Authorization': 'Owner $finalOwnerToken',
          'Content-Type': 'application/json'
        }),
      );
    }

    // 3. Confirm upload
    final confirmRes = await _dio.post(
      '/upload/confirm',
      data: {
        'filename': filename,
        'size': bytes.length,
        'content_type': mimeType,
        'r2_key': r2Key,
      },
      options: Options(headers: {
        'X-Visitor-Token': visitorToken,
        'Content-Type': 'application/json'
      }),
    );

    if (confirmRes.data['success'] != true) {
      throw Exception('Confirmation failed');
    }

    final fileData = confirmRes.data['file'] as Map<String, dynamic>;
    return {
      'id': fileData['id'] as String,
      'share_url': fileData['url'] as String,
      'owner_token': confirmRes.data['owner_token'] as String,
    };
  }

  /// Deletes a file publicly shared on storage.to
  Future<void> deleteShare(String fileId) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId != null && job.ownerToken != null) {
      try {
        await _dio.delete(
          '/file/${job.storageToId}',
          options:
              Options(headers: {'Authorization': 'Owner ${job.ownerToken}'}),
        );
      } catch (e) {
        AppLogger.w('Failed deleteShare: $e', tag: 'WebShareQueue');
      }
    }
    await _box.delete(fileId);
  }

  /// Sets a password on a shared web file on storage.to
  Future<void> setPassword(String fileId, String password) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final res = await _dio.post(
      '/file/${job.storageToId}/password',
      data: {'password': password},
      options: Options(headers: {
        'Authorization': 'Owner ${job.ownerToken}',
        'Content-Type': 'application/json'
      }),
    );

    if (res.data['success'] == true) {
      await _box.put(fileId, job.copyWith(password: password).toMap());
    } else {
      throw Exception(res.data['error'] ?? 'Failed password');
    }
  }

  /// Changes a file's expiration days (1-7)
  Future<void> setExpiry(String fileId, int days) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final res = await _dio.post(
      '/file/${job.storageToId}/expiry',
      data: {'days': days},
      options: Options(headers: {
        'Authorization': 'Owner ${job.ownerToken}',
        'Content-Type': 'application/json'
      }),
    );

    if (res.data['success'] == true) {
      await _box.put(fileId, job.copyWith(expiryDays: days).toMap());
    } else {
      throw Exception(res.data['error'] ?? 'Failed expiry');
    }
  }

  /// Sets a download cap (burn-after-N-downloads)
  Future<void> setMaxDownloads(String fileId, int? maxDownloads) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;
    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final res = await _dio.post(
      '/file/${job.storageToId}/max-downloads',
      data: {'max_downloads': maxDownloads},
      options: Options(headers: {
        'Authorization': 'Owner ${job.ownerToken}',
        'Content-Type': 'application/json'
      }),
    );

    if (res.data['success'] == true) {
      await _box.put(fileId, job.copyWith(maxDownloads: maxDownloads).toMap());
    } else {
      throw Exception(res.data['error'] ?? 'Failed limit');
    }
  }

  /// Uploads a thumbnail for a shared web file.
  Future<void> uploadThumbnail(
      String storageToId, String ownerToken, Uint8List imageBytes) async {
    final formData = FormData.fromMap({
      'thumbnail': MultipartFile.fromBytes(imageBytes, filename: 'thumb.jpg'),
    });

    final res = await _dio.post(
      '/file/$storageToId/thumbnail',
      data: formData,
      options: Options(headers: {
        'Authorization': 'Owner $ownerToken',
        'Content-Type': 'multipart/form-data',
      }),
    );

    if (res.data['success'] != true) {
      throw Exception(res.data['error'] ?? 'Thumbnail upload failed');
    }
  }

  /// Poll the bandwidth/quota status for anonymous visitors
  Future<Map<String, dynamic>> getBandwidthStatus() async {
    final visitorToken = await _getOrCreateVisitorToken();
    final res = await _dio.get(
      '/bandwidth/status',
      options: Options(headers: {'X-Visitor-Token': visitorToken}),
    );
    return res.data as Map<String, dynamic>;
  }

  /// Check whether a file is still pending its upload.
  Future<bool> isFilePending(String storageToId) async {
    final res = await _dio.get('/file/$storageToId/status');
    return res.data['pending'] as bool? ?? false;
  }
}
