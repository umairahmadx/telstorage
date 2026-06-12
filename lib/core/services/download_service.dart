import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/chunk_info.dart';
import '../models/file_record.dart';
import '../utils/app_logger.dart';
import '../utils/web_download.dart'
    if (dart.library.io) '../utils/web_download_stub.dart';
import '../utils/native_save_helper.dart'
    if (dart.library.js_interop) '../utils/native_save_stub.dart';
import 'telegram_service.dart';

export '../utils/native_save_helper.dart'
    if (dart.library.js_interop) '../utils/native_save_stub.dart'
    show NativeSaveResult;

class FileCorruptedException implements Exception {
  @override
  String toString() => 'File integrity check failed: SHA-256 hash mismatch';
}

/// Result from [DownloadService.saveAndOpen]
class SaveResult {
  final String? savedPath;
  final String message;
  final bool success;
  const SaveResult(
      {this.savedPath, required this.message, required this.success});
}

/// Handles file download pipeline — non-blocking, works on Web / Android / iOS.
///
/// Download flow:
///   1. Fetch per-file metadata JSON.
///   2. Download all parts (async HTTP).
///   3. Reassemble bytes.
///   4. SHA-256 verification in 1 MB chunks (non-blocking).
///   5. ZIP extraction if needed.
///   6. Save to platform Downloads / Files / browser bar.
class DownloadService {
  final TelegramService _telegram;

  DownloadService(this._telegram);

  // ── Core download pipeline ─────────────────────────────────────────────────

  Future<Uint8List> downloadFile(
    FileRecord record,
    Function(double progress, String status) onProgress,
  ) async {
    try {
      onProgress(0.0, 'Reading file index…');
      AppLogger.d('Downloading: ${record.name}', tag: 'DownloadService');

      // Step 1: Fetch per-file metadata JSON
      final Uint8List metaBytes;
      if (record.metadataFileId != null && record.metadataFileId!.isNotEmpty) {
        metaBytes = await _telegram.downloadByFileId(record.metadataFileId!);
      } else {
        metaBytes = await _telegram.downloadBytes(record.metadataMessageId);
      }

      // Step 2: Parse metadata
      final fileMeta =
          jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
      final isZipped = fileMeta['is_zipped'] as bool? ?? false;
      final chunks = (fileMeta['chunks'] as List)
          .map((c) => ChunkInfo.fromJson(c as Map<String, dynamic>))
          .toList();
      final expectedHash = fileMeta['sha256'] as String;

      AppLogger.d('${chunks.length} part(s), is_zipped: $isZipped',
          tag: 'DownloadService');

      // Step 3: Download all parts
      final builder = BytesBuilder(copy: false);
      for (var i = 0; i < chunks.length; i++) {
        final part = chunks[i];
        final label = part.partName ?? 'part ${i + 1}';
        final partPct = i / chunks.length;

        onProgress(
          0.05 + partPct * 0.70,
          'Downloading $label (${i + 1}/${chunks.length})…',
        );

        final Uint8List partBytes;
        if (part.fileId != null && part.fileId!.isNotEmpty) {
          partBytes = await _telegram.downloadByFileId(part.fileId!);
        } else {
          partBytes = await _telegram.downloadBytes(part.messageId);
        }
        builder.add(partBytes);
      }

      // Step 4: Reassemble
      onProgress(0.77, 'Reassembling…');
      await Future.delayed(Duration.zero);
      final assembled = builder.toBytes();

      // Step 5: SHA-256 verification in 1 MB chunks
      onProgress(0.80, 'Verifying integrity… 0%');
      final actualHash = await _sha256Chunked(
        assembled,
        (pct) =>
            onProgress(0.80 + pct * 0.12, 'Verifying… ${(pct * 100).toInt()}%'),
      );

      Uint8List finalBytes;

      if (isZipped) {
        // Step 6a: Extract ZIP (STORE mode = instant byte unpack)
        onProgress(0.93, 'Extracting…');
        AppLogger.d('Extracting ZIP…', tag: 'DownloadService');
        await Future.delayed(Duration.zero);
        final archive = ZipDecoder().decodeBytes(assembled);
        if (archive.isEmpty) throw Exception('ZIP archive is empty');

        finalBytes = Uint8List.fromList(archive.first.content as List<int>);

        onProgress(0.96, 'Verifying extracted file…');
        final extractedHash = await _sha256Chunked(finalBytes, (_) {});
        if (extractedHash != expectedHash) throw FileCorruptedException();
      } else {
        if (actualHash != expectedHash) throw FileCorruptedException();
        finalBytes = assembled;
      }

      onProgress(1.0, 'Download complete!');
      AppLogger.i(
          '${record.name} — ${(finalBytes.length / 1048576).toStringAsFixed(2)} MB',
          tag: 'DownloadService');
      return finalBytes;
    } catch (e) {
      AppLogger.e('Download failed: $e', tag: 'DownloadService', error: e);
      throw Exception('Download failed: $e');
    }
  }

  // ── Save & Open ────────────────────────────────────────────────────────────

  /// Platform-aware save:
  /// • Web    → browser download bar (immediate, no permission needed)
  /// • Android → public Downloads folder (/storage/emulated/0/Download/)
  /// • iOS    → Documents folder (iOS Files app) + share sheet
  /// • Desktop → Downloads folder, then open
  Future<SaveResult> saveAndOpen(Uint8List bytes, String filename) async {
    if (kIsWeb) {
      triggerWebDownload(bytes, filename);
      return const SaveResult(
        success: true,
        message: '✅ Download started in your browser!',
      );
    }

    // Native: delegate to platform-specific helper
    final result = await saveNative(bytes, filename);
    return SaveResult(
      success: result.success,
      savedPath: result.savedPath,
      message: result.message,
    );
  }

  /// Legacy compatibility — delegates to [saveAndOpen].
  Future<void> saveFile(Uint8List bytes, String filename) async {
    if (kIsWeb) {
      triggerWebDownload(bytes, filename);
      return;
    }
    await saveAndOpen(bytes, filename);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// SHA-256 in 1 MB chunks — yields to event loop every chunk.
  Future<String> _sha256Chunked(
    Uint8List data,
    void Function(double) onProgress,
  ) async {
    const chunkSize = 1024 * 1024;
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);

    for (var offset = 0; offset < data.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, data.length);
      input.add(data.sublist(offset, end));
      onProgress(offset / data.length);
      await Future.delayed(Duration.zero);
    }

    input.close();
    return output.events.single.toString();
  }
}
