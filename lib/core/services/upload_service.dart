import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';
import '../models/chunk_info.dart';
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import 'hive_service.dart';
import 'metadata_service.dart';
import 'notification_service.dart';
import 'telegram_service.dart';

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
class UploadService {
  final TelegramService _telegram;
  final MetadataService _metadata;
  final HiveService _hive;

  UploadService(this._telegram, this._metadata, this._hive);

  static const int _partSize = AppConstants.chunkSizeBytes; // 19 MB

  Future<void> uploadFile(
    Uint8List bytes,
    String name,
    String? folderId,
    Function(double progress, String status) onProgress,
  ) async {
    if (!await Connectivity.hasConnection()) {
      throw OfflineException('Cannot upload: no internet connection.');
    }

    try {
      AppLogger.d('Starting upload for: $name', tag: 'UploadService');
      onProgress(0.0, 'Preparing…');

      final fileId = const Uuid().v4();
      final mimeType = lookupMimeType(name) ?? 'application/octet-stream';
      final sizeMb = bytes.length / 1048576;

      AppLogger.d(
        'Size: ${sizeMb.toStringAsFixed(2)} MB',
        tag: 'UploadService',
      );

      // ── Step 1: SHA-256 in chunks (non-blocking) ───────────────────────────
      onProgress(0.03, 'Verifying file… 0%');
      final hash = await _sha256Chunked(
        bytes,
        (pct) =>
            onProgress(0.03 + pct * 0.07, 'Verifying… ${(pct * 100).toInt()}%'),
      );

      final chunkInfos = <ChunkInfo>[];

      if (bytes.length <= _partSize) {
        // ── Small file: upload directly ───────────────────────────────────────
        onProgress(0.12, 'Uploading "$name"…');
        AppLogger.d('Small file — uploading directly', tag: 'UploadService');

        final result = await _telegram.uploadBytesWithFileId(bytes, name);
        chunkInfos.add(
          ChunkInfo(
            index: 1,
            messageId: result['message_id'] as int,
            fileId: result['file_id'] as String,
            sizeMb: sizeMb,
            partName: name,
          ),
        );
        onProgress(0.85, 'Uploaded!');
      } else {
        // ── Large file: ZIP (store) → split → upload parts ────────────────────
        onProgress(0.12, 'Packaging file…');
        AppLogger.d(
          'Large file — wrapping in ZIP (store mode)',
          tag: 'UploadService',
        );

        // STORE mode = no DEFLATE compression → near-instant, no CPU freeze.
        // Videos/images are already compressed, DEFLATE would give 0% savings.
        final zipBytes = await _wrapInZipStore(bytes, name);
        final parts = _splitBytes(zipBytes);
        final baseName = name.replaceAll(RegExp(r'\.[^.]+$'), '');

        AppLogger.d(
          'ZIP size: ${(zipBytes.length / 1048576).toStringAsFixed(2)} MB, ${parts.length} part(s)',
          tag: 'UploadService',
        );

        for (var i = 0; i < parts.length; i++) {
          final partName = parts.length == 1
              ? '$baseName.zip'
              : '$baseName.zip.${(i + 1).toString().padLeft(3, '0')}';

          onProgress(
            0.15 + (i / parts.length * 0.68),
            'Uploading part ${i + 1}/${parts.length}…',
          );
          AppLogger.d(
            'Part ${i + 1}/${parts.length}: "$partName" (${(parts[i].length / 1048576).toStringAsFixed(2)} MB)',
            tag: 'UploadService',
          );

          final result = await _telegram.uploadBytesWithFileId(
            parts[i],
            partName,
          );
          chunkInfos.add(
            ChunkInfo(
              index: i + 1,
              messageId: result['message_id'] as int,
              fileId: result['file_id'] as String,
              sizeMb: parts[i].length / 1048576,
              partName: partName,
            ),
          );

          // Brief pause between uploads to respect Telegram rate limits
          await Future.delayed(
            const Duration(milliseconds: AppConstants.uploadDelayMs),
          );
        }
      }

      // ── Step 3: Upload per-file metadata JSON ─────────────────────────────
      onProgress(0.85, 'Saving file index…');
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
      };

      final metaResult = await _telegram.uploadBytesWithFileId(
        Uint8List.fromList(utf8.encode(jsonEncode(fileMeta))),
        '$fileId.json',
      );
      fileMeta['metadata_message_id'] = metaResult['message_id'] as int;
      fileMeta['metadata_file_id'] = metaResult['file_id'] as String;

      // ── Step 4: Update global metadata + local Hive ───────────────────────
      onProgress(0.94, 'Updating storage index…');
      final appMeta = await _metadata.fetch();
      await _metadata.addFile(appMeta, fileMeta);
      await _hive.saveFile(FileRecord.fromMap(fileMeta));

      onProgress(1.0, 'Upload complete!');
      AppLogger.i('Upload complete: $name', tag: 'UploadService');

      await NotificationService.instance.showNotification(
        id: name.hashCode,
        title: 'Upload Complete',
        body: '$name has been successfully uploaded.',
      );
    } catch (e) {
      AppLogger.e('Upload failed: $e', tag: 'UploadService', error: e);
      throw Exception('Upload failed: $e');
    }
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
      input.add(data.sublist(offset, end));
      chunk++;

      // Report progress
      onProgress(offset / data.length);

      // Yield to event loop periodically so UI frames can render
      if (chunk % yieldEvery == 0) {
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
    // Yield one frame so the "Packaging…" status text is visible
    await Future.delayed(Duration.zero);

    final archive = Archive();
    // level: 0 = Deflate.NO_COMPRESSION → STORE mode
    archive.add(ArchiveFile(filename, bytes.length, bytes));
    final encoded = ZipEncoder().encode(archive, level: 0);
    return Uint8List.fromList(encoded);
  }

  /// Split [bytes] into ≤ _partSize chunks.
  List<Uint8List> _splitBytes(Uint8List bytes) {
    final parts = <Uint8List>[];
    var offset = 0;
    while (offset < bytes.length) {
      final end = (offset + _partSize).clamp(0, bytes.length);
      parts.add(bytes.sublist(offset, end));
      offset += _partSize;
    }
    return parts;
  }
}
