/*
 * File: upload_service.dart
 * Description: Handles chunked and streaming uploads to Telegram, local thumbnail caching, and metadata indexing.
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';
import '../constants/app_constants.dart';
import '../models/chunk_info.dart';
import '../models/file_record.dart';
import '../models/pending_action.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import '../utils/thumbnail_generator.dart';
import '../utils/thumbnail_helper_native.dart'
    if (dart.library.js_interop) '../utils/thumbnail_helper_web.dart';
import '../utils/file_reader_stub.dart'
    if (dart.library.io) '../utils/file_reader_native.dart';
import '../utils/zip_stream_chunker.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'chunk_resume_service.dart';
import 'hive_service.dart';
import 'metadata_service.dart';
import 'notification_service.dart';
import 'service_locator.dart';
import 'telegram_service.dart';
import 'transfer_concurrency_coordinator.dart';
import 'transfer_queue_service.dart';
import '../models/transfer_task.dart';
import '../errors/result.dart';
import '../events/domain_event_bus.dart';
import 'upload_service_contract.dart';

/// Handles chunked and streaming uploads to Telegram with non-blocking hashing and STORE ZIP packaging.
class UploadService implements UploadServiceContract {
  final TelegramService _telegram;
  final MetadataService _metadata;
  final HiveService _hive;

  UploadService(this._telegram, this._metadata, this._hive);

  static const int _partSize = AppConstants.chunkSizeBytes; // 19 MB

  Future<T> _withRetry<T>(Future<T> Function() fn,
      {int maxAttempts = 3}) async {
    int attempt = 0;
    while (true) {
      try {
        attempt++;
        return await fn();
      } catch (e) {
        if (attempt >= maxAttempts) rethrow;
        AppLogger.w('Upload attempt $attempt failed ($e), retrying…',
            tag: 'UploadService');
        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }
  }

  @override
  Future<Result<Map<String, dynamic>>> uploadFile(
    Uint8List? bytes,
    String name,
    String? folderId,
    Function(double progress, String status) onProgress, {
    String? filePath,
    int? fileLength,
    bool skipGlobalMetadataUpdate = false,
    String? taskId,
    String? precomputedHash,
    int? precomputedCrc,
    Uint8List? precomputedThumbnailBytes,
    String? thumbnailExtension,
  }) async {
    if (!await Connectivity.hasConnection()) {
      return const Failure(
        NetworkFailure('Cannot upload: no internet connection.'),
      );
    }

    return await TransferConcurrencyCoordinator.instance.runGuarded(() async {
      String? transferId;
      try {
        AppLogger.d('Starting upload for: $name', tag: 'UploadService');

        final fileId = taskId ?? const Uuid().v4();
        transferId = fileId;
        final mimeType = lookupMimeType(name) ?? 'application/octet-stream';
        final totalBytes = bytes?.length ??
            (fileLength != null && fileLength > 0 ? fileLength : null) ??
            (filePath != null
                ? (await ZipStreamChunker.hashAndCrcFile(filePath)).fileSize
                : null);
        if (totalBytes == null) {
          return const Failure(
              UnknownFailure('No data or file path provided for upload.'));
        }
        final sizeMb = totalBytes / 1048576;

        final queue = TransferQueueService.instance;
        final existingTask = queue.tasks
            .cast<TransferTask?>()
            .firstWhere((t) => t?.id == fileId, orElse: () => null);
        if (existingTask == null) {
          queue.addTask(TransferTask(
            id: fileId,
            name: name,
            type: TransferType.upload,
            sizeMb: sizeMb,
            addedAt: DateTime.now(),
            status: TransferStatus.preparing,
            currentStage: 'Preparing…',
          ));
        } else {
          queue.updateTask(fileId,
              status: TransferStatus.preparing, currentStage: 'Preparing…');
        }

        void internalOnProgress(double progress, String status) {
          if (TransferQueueService.instance.isCancelled(fileId)) {
            throw Exception('Upload cancelled by user');
          }
          onProgress(progress, status);
          TransferQueueService.instance.updateTask(
            fileId,
            progress: progress,
            currentStage: status,
            status: progress >= 1.0
                ? TransferStatus.completed
                : TransferStatus.uploading,
          );
        }

        AppLogger.d('Size: ${sizeMb.toStringAsFixed(2)} MB',
            tag: 'UploadService');

        // ── Step 1: SHA-256 (precomputed or chunked) ───────────────────────────
        final String hash;
        int crc = precomputedCrc ?? 0;
        if (precomputedHash != null && precomputedHash.isNotEmpty) {
          hash = precomputedHash;
        } else if (filePath != null) {
          internalOnProgress(0.03, 'Verifying file… 0%');
          final hashInfo = await ZipStreamChunker.hashAndCrcFile(
            filePath,
            onProgress: (pct) => internalOnProgress(
                0.03 + pct * 0.07, 'Verifying… ${(pct * 100).toInt()}%'),
          );
          hash = hashInfo.sha256;
          crc = hashInfo.crc32;
        } else {
          internalOnProgress(0.03, 'Verifying file… 0%');
          final hashInfo = await ZipStreamChunker.hashAndCrcBytesChunked(
            bytes!,
            onProgress: (pct) => internalOnProgress(
                0.03 + pct * 0.07, 'Verifying… ${(pct * 100).toInt()}%'),
          );
          hash = hashInfo.sha256;
          crc = hashInfo.crc32;
        }

        // ── Step 1.2: Check for SHA-256 Deduplication ──────────────────────────
        final existingFile = _hive.allFiles.firstWhere(
          (f) =>
              f.sha256Hash == hash &&
              (f.sizeMb - sizeMb).abs() < 0.01 &&
              f.metadataFileId != null,
          orElse: () => FileRecord.empty(),
        );

        if (existingFile.fileId.isNotEmpty &&
            existingFile.metadataFileId != null) {
          AppLogger.i(
              'Duplicate file hash detected for $name — linking existing remote chunks instantly!',
              tag: 'UploadService');
          internalOnProgress(0.90, 'Instant deduplication copy…');

          final fileMeta = <String, dynamic>{
            'file_id': fileId,
            'name': name,
            'folder_id': folderId,
            'sha256': hash,
            'size_mb': sizeMb,
            'mime_type': mimeType,
            'chunk_count': existingFile.chunkCount,
            'uploaded_at': DateTime.now().toIso8601String(),
            'metadata_message_id': existingFile.metadataMessageId,
            'metadata_file_id': existingFile.metadataFileId,
            if (existingFile.thumbnailFileId != null)
              'thumbnail_file_id': existingFile.thumbnailFileId,
          };

          final savedFile = FileRecord.fromMap(fileMeta);
          await _hive.saveFile(savedFile);
          DomainEventBus.instance.fire(FileUploadedEvent(savedFile));

          if (!skipGlobalMetadataUpdate) {
            try {
              final appMeta = await _metadata.fetch();
              await _metadata.addFile(appMeta, fileMeta);
            } catch (_) {}
          }

          internalOnProgress(1.0, 'Upload complete (Instant Deduplication)!');
          TransferQueueService.instance
              .updateTask(fileId, status: TransferStatus.completed);

          await NotificationService.instance.showCompletionNotification(
            title: 'Instant Upload Complete',
            body: '$name linked instantly via deduplication.',
            payload: 'transfer_upload',
            actions: const [
              AndroidNotificationAction('view_uploads', 'View Uploads',
                  showsUserInterface: true),
            ],
          );

          return Success(fileMeta);
        }

        // ── Step 1.5: Generate and Upload Thumbnail ────────────────────────────
        final resume = ChunkResumeService.instance;
        String? thumbnailFileId = resume.getCachedThumbnailFileId(hash);
        int? thumbnailMessageId = resume.getCachedThumbnailMessageId(hash);

        if (thumbnailFileId == null) {
          try {
            final Uint8List? thumbBytes;
            final String ext;
            if (precomputedThumbnailBytes != null) {
              thumbBytes = precomputedThumbnailBytes;
              ext = thumbnailExtension ?? 'jpg';
            } else {
              internalOnProgress(0.08, 'Generating thumbnail…');
              final gen = await ThumbnailGenerator.generate(
                bytes: bytes,
                filePath: filePath,
                filename: name,
                mimeType: mimeType,
              );
              thumbBytes = gen?.bytes;
              ext = gen?.extension ?? 'jpg';
            }

            if (thumbBytes != null) {
              try {
                ServiceLocator.instance.thumbnailRepository
                    .addToMemoryCache(fileId, thumbBytes);
                await ThumbnailHelper.cacheThumbnail(fileId, thumbBytes);
              } catch (_) {}

              internalOnProgress(0.10, 'Uploading thumbnail…');
              final thumbUpload = await _telegram.uploadBytesWithFileId(
                thumbBytes,
                '.thumb_$name.$ext',
              );
              thumbnailFileId = thumbUpload['file_id'] as String?;
              thumbnailMessageId = thumbUpload['message_id'] as int?;
              if (thumbnailFileId != null) {
                await resume.saveThumbnailFileId(hash, thumbnailFileId);
              }
              if (thumbnailMessageId != null) {
                await resume.saveThumbnailMessageId(hash, thumbnailMessageId);
              }
            }
          } catch (e) {
            AppLogger.e('Thumbnail upload step failed for $name: $e',
                tag: 'UploadService');
          }
        }

        final chunkInfos = <ChunkInfo>[];

        if (totalBytes <= _partSize) {
          // ── Small file: upload directly ───────────────────────────────────────
          internalOnProgress(0.12, 'Uploading "$name"…');
          AppLogger.d('Small file — uploading directly', tag: 'UploadService');

          final Uint8List uploadPayload;
          if (bytes != null) {
            uploadPayload = bytes;
          } else {
            uploadPayload = await readFileBytes(filePath!);
          }

          final result = await _withRetry(
              () => _telegram.uploadBytesWithFileId(uploadPayload, name));
          chunkInfos.add(ChunkInfo(
            index: 1,
            messageId: result['message_id'] as int,
            fileId: result['file_id'] as String,
            sizeMb: sizeMb,
            partName: name,
          ));
          internalOnProgress(0.85, 'Uploaded!');
        } else {
          // ── Large file: ZIP (store) → split → upload parts ────────────────────
          internalOnProgress(0.12, 'Packaging file…');
          AppLogger.d('Large file — streaming in ZIP (store mode)',
              tag: 'UploadService');

          final chunker = ZipStreamChunker(
            filename: name,
            fileSize: totalBytes,
            crc32: crc,
            bytes: bytes,
            filePath: filePath,
            chunkSize: _partSize,
          );
          final totalParts = chunker.partCount;
          final baseName = name.replaceAll(RegExp(r'\.[^.]+$'), '');

          AppLogger.d(
              'ZIP size: ${(chunker.totalZipSize / 1048576).toStringAsFixed(2)} MB, $totalParts part(s)',
              tag: 'UploadService');

          final existingChunks =
              ChunkResumeService.instance.getUploadedChunks(hash);

          for (var i = 0; i < totalParts; i++) {
            final chunkIndex = i + 1;
            // Check for pause/cancel
            while (TransferQueueService.instance.isPaused(fileId) &&
                !TransferQueueService.instance.isCancelled(fileId)) {
              await Future.delayed(const Duration(seconds: 1));
            }
            if (TransferQueueService.instance.isCancelled(fileId)) {
              throw Exception('Upload cancelled by user');
            }

            final partName = totalParts == 1
                ? '$baseName.zip'
                : '$baseName.zip.${chunkIndex.toString().padLeft(3, '0')}';

            final cachedChunk = existingChunks[chunkIndex];
            if (cachedChunk != null) {
              AppLogger.d(
                  'Resuming already-uploaded part $chunkIndex/$totalParts: "$partName"',
                  tag: 'UploadService');
              chunkInfos.add(cachedChunk);
              internalOnProgress(
                0.15 + (i / totalParts * 0.68),
                'Resumed part $chunkIndex/$totalParts…',
              );
              continue;
            }

            internalOnProgress(
              0.15 + (i / totalParts * 0.68),
              'Uploading part $chunkIndex/$totalParts…',
            );

            final partBytes = await chunker.readPart(chunkIndex);
            AppLogger.d(
                'Part $chunkIndex/$totalParts: "$partName" (${(partBytes.length / 1048576).toStringAsFixed(2)} MB)',
                tag: 'UploadService');

            final result = await _withRetry(
                () => _telegram.uploadBytesWithFileId(partBytes, partName));
            final chunkInfo = ChunkInfo(
              index: chunkIndex,
              messageId: result['message_id'] as int,
              fileId: result['file_id'] as String,
              sizeMb: partBytes.length / 1048576,
              partName: partName,
            );
            chunkInfos.add(chunkInfo);
            await ChunkResumeService.instance
                .saveUploadedChunk(hash, chunkIndex, chunkInfo);
          }
        }

        // ── Step 3: Upload per-file metadata JSON ─────────────────────────────
        internalOnProgress(0.85, 'Saving file index…');
        final fileMeta = <String, dynamic>{
          'file_id': fileId,
          'name': name,
          'folder_id': folderId,
          'sha256': hash,
          'size_mb': sizeMb,
          'mime_type': mimeType,
          'chunk_count': chunkInfos.length,
          'is_zipped': totalBytes > _partSize,
          'chunks': chunkInfos.map((c) => c.toJson()).toList(),
          'uploaded_at': DateTime.now().toIso8601String(),
          if (thumbnailFileId != null) 'thumbnail_file_id': thumbnailFileId,
          if (thumbnailMessageId != null)
            'thumbnail_message_id': thumbnailMessageId,
        };

        final metaResult = await _telegram.uploadBytesWithFileId(
          Uint8List.fromList(utf8.encode(jsonEncode(fileMeta))),
          '$fileId.json',
        );
        fileMeta['metadata_message_id'] = metaResult['message_id'] as int;
        fileMeta['metadata_file_id'] = metaResult['file_id'] as String;

        // ── Step 4: Save to local Hive + batch or single metadata update ──────
        internalOnProgress(0.94, 'Updating storage index…');
        final savedFile = FileRecord.fromMap(fileMeta);
        await _hive.saveFile(savedFile);
        DomainEventBus.instance.fire(FileUploadedEvent(savedFile));

        // Clean up cached chunk and thumbnail references upon successful commit
        await ChunkResumeService.instance.clearFileCache(hash);

        if (!skipGlobalMetadataUpdate) {
          try {
            final appMeta = await _metadata.fetch();
            await _metadata.addFile(appMeta, fileMeta);
          } catch (e) {
            AppLogger.w(
                'Direct metadata update failed ($e), enqueuing background sync',
                tag: 'UploadService');
            final pending = PendingAction(
              id: const Uuid().v4(),
              actionType: AppConstants.actionAddFileMeta,
              payload: {'fileMeta': fileMeta},
              timestamp: DateTime.now(),
            );
            if (Hive.isBoxOpen(AppConstants.pendingActionsBox)) {
              await Hive.box<PendingAction>(AppConstants.pendingActionsBox)
                  .put(pending.id, pending);
              ServiceLocator.instance.syncQueue.processQueue();
            }
          }
        }

        internalOnProgress(1.0, 'Upload complete!');
        TransferQueueService.instance
            .updateTask(fileId, status: TransferStatus.completed);
        AppLogger.i('Upload complete: $name', tag: 'UploadService');

        await NotificationService.instance.showCompletionNotification(
          title: 'Upload Complete',
          body: '$name has been successfully uploaded.',
          payload: 'transfer_upload',
          actions: const [
            AndroidNotificationAction('view_uploads', 'View Uploads',
                showsUserInterface: true),
          ],
        );

        return Success(fileMeta);
      } catch (e, st) {
        final wasCancelled = transferId != null &&
            TransferQueueService.instance.isCancelled(transferId);
        if (transferId != null) {
          TransferQueueService.instance.updateTask(
            transferId,
            status:
                wasCancelled ? TransferStatus.cancelled : TransferStatus.failed,
            error: wasCancelled ? null : e.toString(),
          );
        }
        AppLogger.e('Upload failed: $e',
            tag: 'UploadService', error: e, stackTrace: st);
        if (wasCancelled) return const Failure(CancelledFailure());
        if (e is OfflineException || e.toString().contains('OfflineException')) {
          return Failure(NetworkFailure(e.toString(), e));
        }
        return Failure(UnknownFailure('Upload failed: $e', e));
      }
    });
  }

  /// Batch update global metadata in 1 single API call for multi-file uploads.
  Future<void> commitUploadBatch(
      List<Map<String, dynamic>> filesDataList) async {
    await _metadata.addBatchFiles(filesDataList);
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Split [bytes] into chunks of size <= [partSize] using zero-copy typed data views.
  static List<Uint8List> splitBytesZeroCopy(
    Uint8List bytes, [
    int partSize = _partSize,
  ]) {
    final parts = <Uint8List>[];
    var offset = 0;
    while (offset < bytes.length) {
      final end = (offset + partSize).clamp(0, bytes.length);
      parts.add(Uint8List.sublistView(bytes, offset, end));
      offset += partSize;
    }
    return parts;
  }
}
