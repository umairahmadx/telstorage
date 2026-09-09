/*
 * File: zip_stream_chunker.dart
 * Description: Low-memory streaming chunker slicing files into STORE ZIP parts on-the-fly for Telegram upload.
 */

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import '../constants/app_constants.dart';
import 'zip_stream_native.dart'
    if (dart.library.js_interop) 'zip_stream_web.dart';

/// Low-memory streaming chunker slicing files into standard STORE-mode ZIP chunks.
///
/// Ensures memory ceiling is bounded strictly to 1 chunk (< 20 MB) during upload,
/// without buffering entire files in RAM or creating multi-hundred-megabyte temporary files on disk.
class ZipStreamChunker {
  /// Default part chunk size (19 MB).
  static const int defaultPartSize = AppConstants.chunkSizeBytes;

  /// Target file name inside the ZIP container.
  final String filename;

  /// Total uncompressed size of the target payload.
  final int fileSize;

  /// CRC-32 checksum of the uncompressed file.
  final int crc32;

  /// Optional in-memory byte buffer (e.g. Web or small in-memory uploads).
  final Uint8List? bytes;

  /// Optional filesystem path to stream from disk without RAM buffering.
  final String? filePath;

  /// Chunk size in bytes (defaults to 19 MB).
  final int chunkSize;

  /// Cached local header binary slice.
  late final Uint8List localHeader;

  /// Cached central directory and EOCD binary slice.
  late final Uint8List trailer;

  /// Total virtual ZIP byte stream size (header + file payload + trailer).
  late final int totalZipSize;

  /// Total number of 19MB parts.
  late final int partCount;

  ZipStreamChunker({
    required this.filename,
    required this.fileSize,
    required this.crc32,
    this.bytes,
    this.filePath,
    this.chunkSize = defaultPartSize,
    DateTime? modTime,
  }) : assert(bytes != null || filePath != null,
            'ZipStreamChunker must have either in-memory bytes or a filesystem filePath.') {
    localHeader = createLocalHeader(
      filename: filename,
      crc32: crc32,
      fileSize: fileSize,
      modTime: modTime,
    );
    trailer = createCentralDirectoryAndEocd(
      filename: filename,
      crc32: crc32,
      fileSize: fileSize,
      modTime: modTime,
    );
    totalZipSize = localHeader.length + fileSize + trailer.length;
    partCount = (totalZipSize + chunkSize - 1) ~/ chunkSize;
  }

  /// Computes SHA-256 and CRC-32 for a file on disk in streaming chunks without loading it into RAM.
  static Future<({String sha256, int crc32, int fileSize})> hashAndCrcFile(
    String filePath, {
    void Function(double progress)? onProgress,
  }) async {
    return await hashAndCrcPath(filePath, onProgress: onProgress);
  }

  /// Computes SHA-256 and CRC-32 for in-memory bytes with progress callback.
  static Future<({String sha256, int crc32, int fileSize})> hashAndCrcBytesChunked(
    Uint8List data, {
    void Function(double progress)? onProgress,
  }) async {
    const chunkSize = 1024 * 1024;
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    int crc = 0;

    for (var offset = 0; offset < data.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, data.length);
      final slice = Uint8List.sublistView(data, offset, end);
      input.add(slice);
      crc = getCrc32(slice, crc);
      if (onProgress != null && data.isNotEmpty) {
        onProgress(offset / data.length);
      }
      await Future.delayed(Duration.zero);
    }
    input.close();

    return (
      sha256: output.events.single.toString(),
      crc32: crc,
      fileSize: data.length,
    );
  }

  /// Computes SHA-256 and CRC-32 for in-memory bytes synchronously.
  static ({String sha256, int crc32, int fileSize}) hashAndCrcBytes(
    Uint8List bytes,
  ) {
    return (
      sha256: sha256.convert(bytes).toString(),
      crc32: getCrc32(bytes),
      fileSize: bytes.length,
    );
  }

  /// Generates the standard 30-byte + filename Local File Header for a STORE zip entry.
  static Uint8List createLocalHeader({
    required String filename,
    required int crc32,
    required int fileSize,
    DateTime? modTime,
  }) {
    final nameBytes = utf8.encode(filename);
    final header = ByteData(30 + nameBytes.length);
    final time = modTime ?? DateTime.now();
    final dosTime = (time.hour << 11) | (time.minute << 5) | (time.second >> 1);
    final dosDate = ((time.year - 1980) << 9) | (time.month << 5) | time.day;

    header.setUint32(0, 0x04034b50, Endian.little);
    header.setUint16(4, 20, Endian.little); // version needed
    header.setUint16(6, 0x0800, Endian.little); // UTF-8 filename flag
    header.setUint16(8, 0, Endian.little); // compression = STORE (0)
    header.setUint16(10, dosTime, Endian.little);
    header.setUint16(12, dosDate, Endian.little);
    header.setUint32(14, crc32, Endian.little);
    header.setUint32(18, fileSize, Endian.little); // compressed size
    header.setUint32(22, fileSize, Endian.little); // uncompressed size
    header.setUint16(26, nameBytes.length, Endian.little);
    header.setUint16(28, 0, Endian.little); // extra field length

    final result = header.buffer.asUint8List();
    result.setRange(30, 30 + nameBytes.length, nameBytes);
    return result;
  }

  /// Generates Central Directory Header and End of Central Directory (EOCD) records.
  static Uint8List createCentralDirectoryAndEocd({
    required String filename,
    required int crc32,
    required int fileSize,
    DateTime? modTime,
  }) {
    final nameBytes = utf8.encode(filename);
    final cdHeaderSize = 46 + nameBytes.length;
    const eocdSize = 22;
    final buffer = ByteData(cdHeaderSize + eocdSize);
    final time = modTime ?? DateTime.now();
    final dosTime = (time.hour << 11) | (time.minute << 5) | (time.second >> 1);
    final dosDate = ((time.year - 1980) << 9) | (time.month << 5) | time.day;

    // Central Directory Header
    buffer.setUint32(0, 0x02014b50, Endian.little);
    buffer.setUint16(4, 20, Endian.little); // version made by
    buffer.setUint16(6, 20, Endian.little); // version needed
    buffer.setUint16(8, 0x0800, Endian.little); // UTF-8 flag
    buffer.setUint16(10, 0, Endian.little); // compression = STORE
    buffer.setUint16(12, dosTime, Endian.little);
    buffer.setUint16(14, dosDate, Endian.little);
    buffer.setUint32(16, crc32, Endian.little);
    buffer.setUint32(20, fileSize, Endian.little);
    buffer.setUint32(24, fileSize, Endian.little);
    buffer.setUint16(28, nameBytes.length, Endian.little);
    buffer.setUint16(30, 0, Endian.little); // extra field length
    buffer.setUint16(32, 0, Endian.little); // file comment length
    buffer.setUint16(34, 0, Endian.little); // disk number start
    buffer.setUint16(36, 0, Endian.little); // internal attributes
    buffer.setUint32(38, 0x01a40000, Endian.little); // external attributes (0644)
    buffer.setUint32(42, 0, Endian.little); // relative offset of local header

    final result = buffer.buffer.asUint8List();
    result.setRange(46, 46 + nameBytes.length, nameBytes);

    // EOCD Record
    final eocdOffset = cdHeaderSize;
    final localHeaderSize = 30 + nameBytes.length;
    final offsetOfCd = localHeaderSize + fileSize;

    buffer.setUint32(eocdOffset, 0x06054b50, Endian.little);
    buffer.setUint16(eocdOffset + 4, 0, Endian.little);
    buffer.setUint16(eocdOffset + 6, 0, Endian.little);
    buffer.setUint16(eocdOffset + 8, 1, Endian.little); // entries on disk
    buffer.setUint16(eocdOffset + 10, 1, Endian.little); // total entries
    buffer.setUint32(eocdOffset + 12, cdHeaderSize, Endian.little);
    buffer.setUint32(eocdOffset + 16, offsetOfCd, Endian.little);
    buffer.setUint16(eocdOffset + 20, 0, Endian.little);

    return result;
  }

  /// Slices and returns bytes for [partIndex] (1-indexed, 1 <= partIndex <= partCount).
  ///
  /// Bounded strictly to [chunkSize] bytes RAM overhead.
  Future<Uint8List> readPart(int partIndex) async {
    if (partIndex < 1 || partIndex > partCount) {
      throw RangeError('Invalid partIndex: $partIndex (total parts: $partCount)');
    }

    final partStart = (partIndex - 1) * chunkSize;
    final partEnd = min(partIndex * chunkSize, totalZipSize);

    final headerLen = localHeader.length;
    final fileEndInZip = headerLen + fileSize;

    final builder = BytesBuilder(copy: false);

    // 1. Local Header segment
    if (partStart < headerLen) {
      final hStart = partStart;
      final hEnd = min(headerLen, partEnd);
      builder.add(localHeader.sublist(hStart, hEnd));
    }

    // 2. File Payload segment
    if (partEnd > headerLen && partStart < fileEndInZip) {
      final fStartInZip = max(headerLen, partStart);
      final fEndInZip = min(fileEndInZip, partEnd);
      final offsetInFile = fStartInZip - headerLen;
      final lengthToRead = fEndInZip - fStartInZip;

      if (lengthToRead > 0) {
        if (bytes != null) {
          builder.add(Uint8List.sublistView(
            bytes!,
            offsetInFile,
            offsetInFile + lengthToRead,
          ));
        } else {
          final diskBytes = await readDiskSlice(
            filePath!,
            offsetInFile,
            lengthToRead,
          );
          builder.add(diskBytes);
        }
      }
    }

    // 3. Central Directory & EOCD Trailer segment
    if (partEnd > fileEndInZip) {
      final tStartInZip = max(fileEndInZip, partStart);
      final tEndInZip = partEnd;
      final offsetInTrailer = tStartInZip - fileEndInZip;
      final lenInTrailer = tEndInZip - tStartInZip;

      if (lenInTrailer > 0) {
        builder.add(trailer.sublist(
          offsetInTrailer,
          offsetInTrailer + lenInTrailer,
        ));
      }
    }

    return builder.takeBytes();
  }
}
