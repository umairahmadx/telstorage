import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../models/file_record.dart';
import '../models/web_share_job.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import 'download_service.dart';

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
      token = 'visitor_${const Uuid().v4().replaceAll('-', '').substring(0, 16)}';
      await storage.write(key: 'visitor_token', value: token);
    }
    return token;
  }

  /// Enqueue a file to be shared publicly on storage.to
  Future<void> enqueueShare(FileRecord file) async {
    final existingMap = _box.get(file.fileId);
    if (existingMap != null) {
      final existingJob = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));
      if (existingJob.isComplete) {
        AppLogger.i('Web share already completed for: ${file.name}', tag: 'WebShareQueue');
        return;
      }
      if (existingJob.status == 'queued' ||
          existingJob.status == 'downloading' ||
          existingJob.status == 'uploading') {
        return;
      }
      // Retry/resume failed job
      final job = existingJob.copyWith(
        status: 'queued',
        progress: 0.0,
        error: null,
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
      );
      await _box.put(file.fileId, job.toMap());
    }

    _processQueue();
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
      final localCachedFile = Hive.box<FileRecord>(AppConstants.filesBox).get(current.fileId);
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
        },
      );

      // ── Step 2: Upload to storage.to (40% - 95%) ───────────────────────────
      current = current.copyWith(status: 'uploading', progress: 0.40);
      await _box.put(current.fileId, current.toMap());

      final uploadResult = await _uploadToStorageTo(
        bytes: bytes,
        filename: current.name,
        mimeType: current.mimeType,
        visitorToken: visitorToken,
        onProgress: (pct) async {
          current = current.copyWith(
            progress: 0.40 + pct * 0.55,
          );
          await _box.put(current.fileId, current.toMap());
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
      AppLogger.i('Web share completed successfully for: ${current.name}', tag: 'WebShareQueue');

    } catch (e) {
      AppLogger.e('Web share failed for ${current.name}: $e', tag: 'WebShareQueue');
      current = current.copyWith(
        status: 'failed',
        error: e.toString(),
      );
      await _box.put(current.fileId, current.toMap());
    }
  }

  /// Internal helper to perform storage.to upload dance
  Future<Map<String, dynamic>> _uploadToStorageTo({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required String visitorToken,
    required void Function(double pct) onProgress,
  }) async {
    // 1. Init upload
    AppLogger.d('Initializing storage.to upload for $filename...', tag: 'WebShareQueue');
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

      AppLogger.d('Uploading file to Cloudflare R2...', tag: 'WebShareQueue');
      await _dio.put(
        uploadUrl,
        data: Stream.fromIterable([bytes]),
        options: Options(
          // The default API timeout is intentionally short. A signed R2 PUT,
          // however, cannot respond until the complete file has transferred.
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

      AppLogger.d('Uploading multipart file to R2 ($totalParts parts)...', tag: 'WebShareQueue');
      final List<Map<String, dynamic>> completedParts = [];

      for (var i = 0; i < totalParts; i++) {
        final partNumber = i + 1;
        final start = i * partSize;
        final end = (start + partSize).clamp(0, bytes.length);
        final partBytes = bytes.sublist(start, end);

        // Fetch URL for this part
        String partUrl = initialUrls[partNumber.toString()] as String? ?? '';
        if (partUrl.isEmpty) {
          final partUrlRes = await _dio.post(
            '/upload/parts',
            data: {
              'upload_id': uploadId,
              'part_numbers': [partNumber]
            },
            options: Options(
              headers: {
                'Authorization': 'Owner $finalOwnerToken',
              },
            ),
          );
          if (partUrlRes.data['success'] == true) {
            final partUrls = partUrlRes.data['part_urls'] as List;
            if (partUrls.isNotEmpty) {
              partUrl = partUrls.first['url'] as String;
            }
          }
        }

        if (partUrl.isEmpty) {
          throw Exception('Failed to get signed R2 URL for part $partNumber');
        }

        // PUT part bytes to R2
        final res = await _dio.put(
          partUrl,
          data: Stream.fromIterable([partBytes]),
          options: Options(
            // Multipart uploads need the same allowance per part; otherwise a
            // slow connection still hits the global 30-second API timeout.
            sendTimeout: _r2TransferTimeout(partBytes.length),
            receiveTimeout: _r2TransferTimeout(partBytes.length),
            headers: {
              Headers.contentLengthHeader: partBytes.length,
              Headers.contentTypeHeader: mimeType,
            },
          ),
          onSendProgress: (sent, total) {
            final partPct = total > 0 ? sent / total : 0.0;
            final overallPct = (i + partPct) / totalParts;
            onProgress(overallPct);
          },
        );

        final etag = res.headers.value('etag') ?? res.headers.value('ETag') ?? '';
        if (etag.isEmpty) {
          throw Exception('Failed to retrieve ETag for part $partNumber');
        }

        completedParts.add({
          'partNumber': partNumber,
          'etag': etag,
        });
      }

      // Complete Multipart
      AppLogger.d('Finalizing multipart upload...', tag: 'WebShareQueue');
      await _dio.post(
        '/upload/complete-multipart',
        data: {
          'upload_id': uploadId,
          'parts': completedParts,
        },
        options: Options(
          headers: {
            'Authorization': 'Owner $finalOwnerToken',
            'Content-Type': 'application/json',
          },
        ),
      );
    }

    // 3. Confirm upload
    AppLogger.d('Confirming storage.to upload...', tag: 'WebShareQueue');
    final confirmRes = await _dio.post(
      '/upload/confirm',
      data: {
        'filename': filename,
        'size': bytes.length,
        'content_type': mimeType,
        'r2_key': r2Key,
      },
      options: Options(
        headers: {
          'X-Visitor-Token': visitorToken,
          'Content-Type': 'application/json',
        },
      ),
    );

    if (confirmRes.data['success'] != true) {
      throw Exception(confirmRes.data['error'] ?? 'Confirmation failed');
    }

    final fileData = confirmRes.data['file'] as Map<String, dynamic>;
    final ownerToken = confirmRes.data['owner_token'] as String;

    return {
      'id': fileData['id'] as String,
      'share_url': fileData['url'] as String,
      'owner_token': ownerToken,
    };
  }

  /// Deletes a file publicly shared on storage.to
  Future<void> deleteShare(String fileId) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;

    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId != null && job.ownerToken != null) {
      try {
        AppLogger.i('Deleting public file from storage.to: ${job.storageToId}', tag: 'WebShareQueue');
        await _dio.delete(
          '/file/${job.storageToId}',
          options: Options(
            headers: {
              'Authorization': 'Owner ${job.ownerToken}',
            },
          ),
        );
      } catch (e) {
        AppLogger.w('Failed to delete file from storage.to server: $e', tag: 'WebShareQueue');
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
      options: Options(
        headers: {
          'Authorization': 'Owner ${job.ownerToken}',
          'Content-Type': 'application/json',
        },
      ),
    );

    if (res.data['success'] == true) {
      final updated = job.copyWith(password: password);
      await _box.put(fileId, updated.toMap());
    } else {
      throw Exception(res.data['error'] ?? 'Failed to set password');
    }
  }

  /// Removes password from a shared web file
  Future<void> removePassword(String fileId) async {
    final existingMap = _box.get(fileId);
    if (existingMap == null) return;

    final job = WebShareJob.fromMap(Map<dynamic, dynamic>.from(existingMap));

    if (job.storageToId == null || job.ownerToken == null) return;

    final res = await _dio.delete(
      '/file/${job.storageToId}/password',
      options: Options(
        headers: {
          'Authorization': 'Owner ${job.ownerToken}',
        },
      ),
    );

    if (res.data['success'] == true) {
      final updated = job.copyWith(password: null);
      await _box.put(fileId, updated.toMap());
    } else {
      throw Exception(res.data['error'] ?? 'Failed to remove password');
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
      options: Options(
        headers: {
          'Authorization': 'Owner ${job.ownerToken}',
          'Content-Type': 'application/json',
        },
      ),
    );

    if (res.data['success'] == true) {
      final updated = job.copyWith(maxDownloads: maxDownloads);
      await _box.put(fileId, updated.toMap());
    } else {
      throw Exception(res.data['error'] ?? 'Failed to set download cap');
    }
  }
}
