/*
 * File: upload_service.dart
 * Description: Handles chunked and streaming uploads to Telegram, local thumbnail caching, and metadata indexing.
 */

import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
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
import 'package:flutter/foundation.dart' show kIsWeb;
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

/// Handles file upload pipeline — non-blocking on Flutter web (single JS thread).
///
/// Strategy:
///   • Files ≤ 19 MB  →  upload directly as original filename.
///   • Files > 19 MB  →  wrap in ZIP (STORE mode, no DEFLATE compression) →
///                        split into 19 MB parts → upload each as name.zip.001…
///
/// SHA-256 is computed in 1 MB chunks with event-loop yields between each
/// chunk so the UI never freezes.  ZIP uses STORE mode which is near-instant
/// (no CPU compression needed since MP4/JPG/etc are already compressed).
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
    Uint8List bytes,
    String name,
    String? folderId,
    Function(double progress, String status) onProgress, {
    bool skipGlobalMetadataUpdate = false,
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

        final fileId = const Uuid().v4();
        transferId = fileId;
        final mimeType = lookupMimeType(name) ?? 'application/octet-stream';
        final sizeMb = bytes.length / 1048576;

        final task = TransferTask(
          id: fileId,
          name: name,
          type: TransferType.upload,
          sizeMb: sizeMb,
          addedAt: DateTime.now(),
          status: TransferStatus.preparing,
          currentStage: 'Preparing…',
        );
        TransferQueueService.instance.addTask(task);

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

        // ── Step 1: SHA-256 in chunks (non-blocking) ───────────────────────────
        internalOnProgress(0.03, 'Verifying file… 0%');
        final hash = await _sha256Chunked(
          bytes,
          (pct) => internalOnProgress(
              0.03 + pct * 0.07, 'Verifying… ${(pct * 100).toInt()}%'),
        );

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
            actions: [
              const AndroidNotificationAction(
                'view_uploads',
                'View Uploads',
                showsUserInterface: true,
              ),
            ],
          );

          return Success(fileMeta);
        }

        // ── Step 1.5: Generate and Upload Thumbnail ────────────────────────────
        String? thumbnailFileId =
            ChunkResumeService.instance.getCachedThumbnailFileId(hash);

        if (thumbnailFileId == null) {
          try {
            internalOnProgress(0.08, 'Generating thumbnail…');
            final thumbResult = await ThumbnailGenerator.generate(
              bytes: bytes,
              filename: name,
              mimeType: mimeType,
            );

            if (thumbResult != null) {
              try {
                ServiceLocator.instance.thumbnailRepository
                    .addToMemoryCache(fileId, thumbResult.bytes);
                await ThumbnailHelper.cacheThumbnail(fileId, thumbResult.bytes);
              } catch (_) {}

              internalOnProgress(0.10, 'Uploading thumbnail…');
              final thumbUpload = await _telegram.uploadBytesWithFileId(
                thumbResult.bytes,
                '.thumb_$name.${thumbResult.extension}',
              );
              thumbnailFileId = thumbUpload['file_id'] as String?;
              if (thumbnailFileId != null) {
                await ChunkResumeService.instance
                    .saveThumbnailFileId(hash, thumbnailFileId);
              }
            }
          } catch (e) {
            AppLogger.e('Thumbnail upload step failed for $name: $e',
                tag: 'UploadService');
          }
        }

        final chunkInfos = <ChunkInfo>[];

        if (bytes.length <= _partSize) {
          // ── Small file: upload directly ───────────────────────────────────────
          internalOnProgress(0.12, 'Uploading "$name"…');
          AppLogger.d('Small file — uploading directly', tag: 'UploadService');

          final result = await _withRetry(
              () => _telegram.uploadBytesWithFileId(bytes, name));
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
          AppLogger.d('Large file — wrapping in ZIP (store mode)',
              tag: 'UploadService');

          // STORE mode = no DEFLATE compression → near-instant, no CPU freeze.
          // Videos/images are already compressed, DEFLATE would give 0% savings.
          final zipBytes = await _wrapInZipStore(bytes, name);
          final parts = _splitBytes(zipBytes);
          final baseName = name.replaceAll(RegExp(r'\.[^.]+$'), '');

          AppLogger.d(
              'ZIP size: ${(zipBytes.length / 1048576).toStringAsFixed(2)} MB, ${parts.length} part(s)',
              tag: 'UploadService');

          final existingChunks =
              ChunkResumeService.instance.getUploadedChunks(hash);

          for (var i = 0; i < parts.length; i++) {
            final chunkIndex = i + 1;
            // Check for pause/cancel
            while (TransferQueueService.instance.isPaused(fileId) &&
                !TransferQueueService.instance.isCancelled(fileId)) {
              await Future.delayed(const Duration(seconds: 1));
            }
            if (TransferQueueService.instance.isCancelled(fileId)) {
              throw Exception('Upload cancelled by user');
            }

            final partName = parts.length == 1
                ? '$baseName.zip'
                : '$baseName.zip.${chunkIndex.toString().padLeft(3, '0')}';

            final cachedChunk = existingChunks[chunkIndex];
            if (cachedChunk != null) {
              AppLogger.d(
                  'Resuming already-uploaded part $chunkIndex/${parts.length}: "$partName"',
                  tag: 'UploadService');
              chunkInfos.add(cachedChunk);
              internalOnProgress(
                0.15 + (i / parts.length * 0.68),
                'Resumed part $chunkIndex/${parts.length}…',
              );
              continue;
            }

            internalOnProgress(
              0.15 + (i / parts.length * 0.68),
              'Uploading part $chunkIndex/${parts.length}…',
            );
            AppLogger.d(
                'Part $chunkIndex/${parts.length}: "$partName" (${(parts[i].length / 1048576).toStringAsFixed(2)} MB)',
                tag: 'UploadService');

            final result = await _withRetry(
                () => _telegram.uploadBytesWithFileId(parts[i], partName));
            final chunkInfo = ChunkInfo(
              index: chunkIndex,
              messageId: result['message_id'] as int,
              fileId: result['file_id'] as String,
              sizeMb: parts[i].length / 1048576,
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
          'is_zipped': bytes.length > _partSize,
          'chunks': chunkInfos.map((c) => c.toJson()).toList(),
          'uploaded_at': DateTime.now().toIso8601String(),
          if (thumbnailFileId != null) 'thumbnail_file_id': thumbnailFileId,
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
                'Direct metadata index update failed ($e), enqueuing background sync action',
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
          actions: [
            const AndroidNotificationAction(
              'view_uploads',
              'View Uploads',
              showsUserInterface: true,
            ),
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
        if (wasCancelled) {
          return const Failure(CancelledFailure());
        }
        if (e is OfflineException ||
            e.toString().contains('OfflineException')) {
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

  /// SHA-256 computed in 1 MB chunks.
  ///
  /// Each chunk `add()` is followed by `await Future.delayed(Duration.zero)`
  /// every 4 MB so the Flutter event loop can process a frame and update the
  /// progress text in the UI.  This prevents the "frozen tab" feeling.
  Future<String> _sha256Chunked(
    Uint8List data,
    void Function(double) onProgress,
  ) async {
    const chunkSize = 1024 * 1024; // 1 MB per chunk
    // Yield every single chunk — gives UI a frame per MB, no stutter
    const yieldEvery = 1;

    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);

    var chunk = 0;
    for (var offset = 0; offset < data.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, data.length);
      input.add(Uint8List.sublistView(data, offset, end));
      chunk++;

      // Report progress
      onProgress(offset / data.length);

      // Yield to event loop periodically on Web so UI frames can render
      if (kIsWeb && chunk % yieldEvery == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    input.close();
    return output.events.single.toString();
  }

  /// Wraps [bytes] in a ZIP using STORE (no compression).
  ///
  /// STORE mode simply packs the bytes into the ZIP container without
  /// running DEFLATE.  For already-compressed files (MP4, JPEG, etc.) this
  /// is functionally identical and takes milliseconds instead of seconds.
  Future<Uint8List> _wrapInZipStore(Uint8List bytes, String filename) async {
    // Yield one frame on Web so the "Packaging…" status text is visible
    if (kIsWeb) {
      await Future.delayed(Duration.zero);
    }

    final archive = Archive();
    // level: 0 = Deflate.NO_COMPRESSION → STORE mode
    archive.add(ArchiveFile(filename, bytes.length, bytes));
    final encoded = ZipEncoder().encode(archive, level: 0);
    return Uint8List.fromList(encoded);
  }

  /// Split [bytes] into chunks of size ≤ [partSize] using zero-copy typed data views.
  /// Slices share the original [bytes.buffer] preventing redundant heap memory allocation.
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

  /// Split [bytes] into ≤ _partSize chunks using zero-copy view.
  List<Uint8List> _splitBytes(Uint8List bytes) {
    return splitBytesZeroCopy(bytes, _partSize);
  }
}
