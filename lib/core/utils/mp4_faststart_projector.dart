/*
 * File: mp4_faststart_projector.dart
 * Description: Zero-disk-duplication virtual FastStart projector for MP4/MOV files,
 * reordering moov before mdat in memory without rewriting the file on disk.
 */

import 'dart:io';
import 'dart:typed_data';
import 'app_logger.dart';

/// A virtual byte range segment mapping to either disk or in-memory patched data.
class _VirtualSegment {
  /// If true, bytes come from the in-memory patched moov buffer.
  final bool isMemory;

  /// Byte offset in the source (disk file offset or patched moov buffer offset).
  final int sourceOffset;

  /// Number of bytes in this segment.
  final int length;

  _VirtualSegment({
    required this.isMemory,
    required this.sourceOffset,
    required this.length,
  });
}

/// Minimal descriptor for a top-level MP4 box (atom).
class _BoxInfo {
  final String type;
  final int offset;
  final int size;

  _BoxInfo({required this.type, required this.offset, required this.size});
}

/// Virtual FastStart projector that reorders moov before mdat in an MP4 file
/// without copying or duplicating any bytes on disk.
///
/// When an MP4/MOV file has moov at the end (non-FastStart), this projector
/// reads the moov box into RAM (typically < 2 MB even for multi-hour 4K video),
/// patches all stco/co64 chunk offsets, and presents a virtual byte layout of
/// `ftyp + moov + mdat` that any sequential reader (like [RawStreamChunker])
/// can stream through.
class Mp4FastStartProjector {
  /// Path to the original MP4 file on disk.
  final String filePath;

  /// Total virtual file size (identical to original file size — zero inflation).
  final int virtualSize;

  final List<_VirtualSegment> _segments;
  Uint8List? _patchedMoov;

  /// Virtual byte offset where the moov region ends.
  /// Once all reads are past this point, the RAM buffer is released.
  final int _moovVirtualEnd;

  Mp4FastStartProjector._({
    required this.filePath,
    required this.virtualSize,
    required List<_VirtualSegment> segments,
    required Uint8List patchedMoov,
    required int moovVirtualEnd,
  })  : _segments = segments,
        _patchedMoov = patchedMoov,
        _moovVirtualEnd = moovVirtualEnd;

  /// MP4/MOV/M4V/M4A file extensions eligible for FastStart optimization.
  static const _mp4Extensions = {'.mp4', '.mov', '.m4v', '.m4a'};

  /// Container box types that contain child boxes (must recurse into them for stco/co64 patching).
  static const _containerTypes = {
    'moov', 'trak', 'mdia', 'minf', 'stbl', 'edts', 'dinf', 'udta', 'mvex',
  };

  /// Maximum moov size to load into RAM (200 MB).
  ///
  /// Enterprise safeguard: prevents OOM on mobile devices (4–6 GB RAM) for
  /// extremely long recordings. 200 MB covers ~20 hours of 4K/30fps video
  /// while consuming at most 5% of a budget 4 GB phone's RAM.
  /// Files exceeding this threshold upload without FastStart — the player
  /// still works, just with slower initial buffering (~30s for 100 MB moov).
  static const int _maxMoovSizeBytes = 200 * 1024 * 1024;

  /// Maximum value for a 32-bit unsigned integer (stco offset limit).
  static const int _maxUint32 = 0xFFFFFFFF;

  /// Analyzes the MP4 file at [filePath] and returns a projector if moov is at the end.
  ///
  /// Returns `null` if:
  /// - The file is not an MP4/MOV container.
  /// - The file is already FastStart optimized (moov before mdat).
  /// - The file structure cannot be parsed (graceful degradation).
  static Future<Mp4FastStartProjector?> create({
    required String filePath,
    required int fileSize,
  }) async {
    final lowerPath = filePath.toLowerCase();
    if (!_mp4Extensions.any((ext) => lowerPath.endsWith(ext))) {
      return null;
    }

    if (fileSize < 16) return null;

    try {
      return await _analyze(filePath, fileSize);
    } catch (e) {
      AppLogger.w(
        '[FASTSTART] Failed to analyze $filePath: $e — uploading without FastStart.',
        tag: 'Mp4FastStartProjector',
      );
      return null;
    }
  }

  static Future<Mp4FastStartProjector?> _analyze(String filePath, int fileSize) async {
    final file = File(filePath);
    final raf = await file.open(mode: FileMode.read);

    try {
      final boxes = await _scanTopLevelBoxes(raf, fileSize);
      if (boxes.isEmpty) return null;

      final moovInfo = boxes.cast<_BoxInfo?>().firstWhere(
        (b) => b?.type == 'moov',
        orElse: () => null,
      );
      final mdatInfo = boxes.cast<_BoxInfo?>().firstWhere(
        (b) => b?.type == 'mdat',
        orElse: () => null,
      );

      if (moovInfo == null || mdatInfo == null) return null;

      // Already FastStart — moov comes before mdat.
      if (moovInfo.offset < mdatInfo.offset) return null;

      // Enterprise guard: moov too large for mobile RAM budget.
      if (moovInfo.size > _maxMoovSizeBytes) {
        AppLogger.w(
          '[FASTSTART] moov box is ${(moovInfo.size / 1048576).toStringAsFixed(1)} MB '
          '(exceeds ${_maxMoovSizeBytes ~/ 1048576} MB cap) — skipping projection to prevent OOM.',
          tag: 'Mp4FastStartProjector',
        );
        return null;
      }

      // Read moov box into RAM and patch chunk offsets.
      await raf.setPosition(moovInfo.offset);
      final moovBytes = Uint8List.fromList(await raf.read(moovInfo.size));
      final patchSuccess = _patchChunkOffsets(moovBytes, moovInfo.size, moovInfo.size);

      // Enterprise guard: stco 32-bit overflow detected (file >4 GB using stco instead of co64).
      if (!patchSuccess) {
        AppLogger.w(
          '[FASTSTART] stco 32-bit overflow detected — skipping projection. '
          'File uses stco for offsets >4 GB; upload will proceed without FastStart.',
          tag: 'Mp4FastStartProjector',
        );
        return null;
      }

      // Build virtual segment map.
      final segments = <_VirtualSegment>[];

      // Segment 1: Pre-mdat bytes from disk (ftyp + any small atoms before mdat).
      if (mdatInfo.offset > 0) {
        segments.add(_VirtualSegment(
          isMemory: false,
          sourceOffset: 0,
          length: mdatInfo.offset,
        ));
      }

      // Segment 2: Patched moov from RAM.
      segments.add(_VirtualSegment(
        isMemory: true,
        sourceOffset: 0,
        length: moovInfo.size,
      ));

      // Segment 3: Everything from mdat start up to moov start (includes mdat + any in-between atoms).
      final mdatToMoovLen = moovInfo.offset - mdatInfo.offset;
      if (mdatToMoovLen > 0) {
        segments.add(_VirtualSegment(
          isMemory: false,
          sourceOffset: mdatInfo.offset,
          length: mdatToMoovLen,
        ));
      }

      // Segment 4: Anything after moov to end of file (rare, but handle gracefully).
      final afterMoovLen = fileSize - (moovInfo.offset + moovInfo.size);
      if (afterMoovLen > 0) {
        segments.add(_VirtualSegment(
          isMemory: false,
          sourceOffset: moovInfo.offset + moovInfo.size,
          length: afterMoovLen,
        ));
      }

      AppLogger.i(
        '[FASTSTART] Virtual projection created for $filePath — moov (${moovInfo.size} bytes) moved before mdat. Zero disk copy.',
        tag: 'Mp4FastStartProjector',
      );

      return Mp4FastStartProjector._(
        filePath: filePath,
        virtualSize: fileSize,
        segments: segments,
        patchedMoov: moovBytes,
        moovVirtualEnd: mdatInfo.offset + moovInfo.size,
      );
    } finally {
      await raf.close();
    }
  }

  /// Scans the file for top-level MP4 boxes (atoms), reading only 8–16 byte headers.
  static Future<List<_BoxInfo>> _scanTopLevelBoxes(
    RandomAccessFile raf,
    int fileSize,
  ) async {
    final boxes = <_BoxInfo>[];
    var offset = 0;

    while (offset + 8 <= fileSize) {
      await raf.setPosition(offset);
      final header = await raf.read(8);
      if (header.length < 8) break;

      final bdata = ByteData.sublistView(Uint8List.fromList(header));
      var size = bdata.getUint32(0);
      final type = String.fromCharCodes(header.sublist(4, 8));

      if (size == 1) {
        // Extended 64-bit size.
        if (offset + 16 > fileSize) break;
        final ext = await raf.read(8);
        if (ext.length < 8) break;
        size = ByteData.sublistView(Uint8List.fromList(ext)).getUint64(0);
      } else if (size == 0) {
        // Box extends to end of file.
        size = fileSize - offset;
      }

      if (size < 8 || offset + size > fileSize) break;
      boxes.add(_BoxInfo(type: type, offset: offset, size: size));
      offset += size;
    }

    return boxes;
  }

  /// Recursively patches all stco (32-bit) and co64 (64-bit) chunk offset tables
  /// inside the moov box by adding [delta] to every entry.
  ///
  /// Returns `false` if any stco offset would overflow 32-bit unsigned range.
  static bool _patchChunkOffsets(Uint8List data, int end, int delta) {
    return _patchRecursive(data, 8, end, delta);
  }

  static bool _patchRecursive(Uint8List data, int start, int end, int delta) {
    var pos = start;
    final bdata = ByteData.sublistView(data);

    while (pos + 8 <= end) {
      var boxSize = bdata.getUint32(pos);
      final type = String.fromCharCodes(data.sublist(pos + 4, pos + 8));
      var headerSize = 8;

      if (boxSize == 1 && pos + 16 <= end) {
        boxSize = bdata.getUint64(pos + 8);
        headerSize = 16;
      } else if (boxSize == 0) {
        boxSize = end - pos;
      }

      if (boxSize < 8 || pos + boxSize > end) break;

      if (type == 'stco') {
        if (!_patchStco32(bdata, pos + headerSize, pos + boxSize, delta)) {
          return false;
        }
      } else if (type == 'co64') {
        _patchCo6464(bdata, pos + headerSize, pos + boxSize, delta);
      } else if (_containerTypes.contains(type)) {
        if (!_patchRecursive(data, pos + headerSize, pos + boxSize, delta)) {
          return false;
        }
      }

      pos += boxSize;
    }
    return true;
  }

  /// Patches stco 32-bit offsets. Returns false if any offset would overflow uint32.
  static bool _patchStco32(ByteData bd, int contentStart, int boxEnd, int delta) {
    if (contentStart + 8 > boxEnd) return true;
    final entryCount = bd.getUint32(contentStart + 4);
    for (var i = 0; i < entryCount; i++) {
      final p = contentStart + 8 + i * 4;
      if (p + 4 > boxEnd) break;
      final original = bd.getUint32(p);
      final patched = original + delta;
      if (patched > _maxUint32) return false;
      bd.setUint32(p, patched);
    }
    return true;
  }

  static void _patchCo6464(ByteData bd, int contentStart, int boxEnd, int delta) {
    if (contentStart + 8 > boxEnd) return;
    final entryCount = bd.getUint32(contentStart + 4);
    for (var i = 0; i < entryCount; i++) {
      final p = contentStart + 8 + i * 8;
      if (p + 8 > boxEnd) break;
      bd.setUint64(p, bd.getUint64(p) + delta);
    }
  }

  /// Reads a virtual byte slice from [start] to [end] across the projected segments,
  /// mapping each range to either the on-disk file or the in-memory patched moov.
  ///
  /// Automatically releases the moov RAM buffer once all reads are past the moov region.
  Future<Uint8List> readSlice(int start, int end) async {
    if (start >= end || start < 0) return Uint8List(0);
    final clampedEnd = end.clamp(start, virtualSize);
    final result = Uint8List(clampedEnd - start);
    var resultOffset = 0;
    var virtualOffset = 0;

    final raf = await File(filePath).open(mode: FileMode.read);
    try {
      for (final seg in _segments) {
        final segStart = virtualOffset;
        final segEnd = virtualOffset + seg.length;

        if (start < segEnd && clampedEnd > segStart) {
          final readStart = (start > segStart) ? start - segStart : 0;
          final readEnd = (clampedEnd < segEnd) ? clampedEnd - segStart : seg.length;
          final readLen = readEnd - readStart;

          if (seg.isMemory && _patchedMoov != null) {
            result.setRange(
              resultOffset,
              resultOffset + readLen,
              _patchedMoov!,
              seg.sourceOffset + readStart,
            );
          } else if (!seg.isMemory) {
            await raf.setPosition(seg.sourceOffset + readStart);
            final bytes = await raf.read(readLen);
            result.setRange(resultOffset, resultOffset + bytes.length, bytes);
          }
          resultOffset += readLen;
        }
        virtualOffset += seg.length;
        if (virtualOffset >= clampedEnd) break;
      }
    } finally {
      await raf.close();
    }

    // Auto-release: once reads are entirely past the moov region, free the RAM buffer.
    if (_patchedMoov != null && start >= _moovVirtualEnd) {
      final releasedMb = (_patchedMoov!.length / 1048576).toStringAsFixed(1);
      _patchedMoov = null;
      AppLogger.i(
        '[FASTSTART] Released $releasedMb MB moov buffer — all moov chunks uploaded, pure disk reads from here.',
        tag: 'Mp4FastStartProjector',
      );
    }

    return result;
  }
}
