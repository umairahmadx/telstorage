/*
 * File: mp4_faststart_projector_test.dart
 * Description: Unit tests for Mp4FastStartProjector validating virtual atom reordering,
 * in-memory stco/co64 offset adjustment, and zero-disk duplication streaming.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telstorage/core/utils/mp4_faststart_projector.dart';
import 'package:telstorage/core/utils/raw_stream_chunker.dart';

Uint8List _createBox(String type, Uint8List payload) {
  final size = 8 + payload.length;
  final bytes = Uint8List(size);
  final bdata = ByteData.sublistView(bytes);
  bdata.setUint32(0, size);
  bytes[4] = type.codeUnitAt(0);
  bytes[5] = type.codeUnitAt(1);
  bytes[6] = type.codeUnitAt(2);
  bytes[7] = type.codeUnitAt(3);
  bytes.setRange(8, size, payload);
  return bytes;
}

Uint8List _createStcoBox(List<int> offsets) {
  final payload = Uint8List(8 + offsets.length * 4);
  final bdata = ByteData.sublistView(payload);
  bdata.setUint8(0, 0); // version
  // 3 bytes flags = 0
  bdata.setUint32(4, offsets.length); // entry count
  for (var i = 0; i < offsets.length; i++) {
    bdata.setUint32(8 + i * 4, offsets[i]);
  }
  return _createBox('stco', payload);
}

Uint8List _createCo64Box(List<int> offsets) {
  final payload = Uint8List(8 + offsets.length * 8);
  final bdata = ByteData.sublistView(payload);
  bdata.setUint8(0, 0); // version
  // 3 bytes flags = 0
  bdata.setUint32(4, offsets.length); // entry count
  for (var i = 0; i < offsets.length; i++) {
    bdata.setUint64(8 + i * 8, offsets[i]);
  }
  return _createBox('co64', payload);
}

Uint8List _createMoovBoxWithStco(List<int> offsets) {
  final stco = _createStcoBox(offsets);
  final stbl = _createBox('stbl', stco);
  final minf = _createBox('minf', stbl);
  final mdia = _createBox('mdia', minf);
  final trak = _createBox('trak', mdia);
  return _createBox('moov', trak);
}

Uint8List _createMoovBoxWithCo64(List<int> offsets) {
  final co64 = _createCo64Box(offsets);
  final stbl = _createBox('stbl', co64);
  final minf = _createBox('minf', stbl);
  final mdia = _createBox('mdia', minf);
  final trak = _createBox('trak', mdia);
  return _createBox('moov', trak);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('faststart_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Mp4FastStartProjector Unit Tests', () {
    test('TC-FS-01: Non-MP4 file returns null (no projection needed)', () async {
      final textFile = File(p.join(tempDir.path, 'document.txt'));
      await textFile.writeAsString('Hello, world! This is a plain text file.');

      final projector = await Mp4FastStartProjector.create(
        filePath: textFile.path,
        fileSize: await textFile.length(),
      );

      expect(projector, isNull);
    });

    test('TC-FS-02: Already FastStart MP4 (moov before mdat) returns null', () async {
      final ftyp = _createBox('ftyp', Uint8List.fromList([1, 2, 3, 4]));
      final moov = _createMoovBoxWithStco([100, 200]);
      final mdat = _createBox('mdat', Uint8List(500));

      final mp4Bytes = Uint8List.fromList([...ftyp, ...moov, ...mdat]);
      final mp4File = File(p.join(tempDir.path, 'already_faststart.mp4'));
      await mp4File.writeAsBytes(mp4Bytes);

      final projector = await Mp4FastStartProjector.create(
        filePath: mp4File.path,
        fileSize: mp4Bytes.length,
      );

      expect(projector, isNull);
    });

    test('TC-FS-03: MP4 with moov at end patches stco offsets and projects virtually', () async {
      final ftyp = _createBox('ftyp', Uint8List.fromList([1, 2, 3, 4]));
      final mdat = _createBox('mdat', Uint8List.fromList(List.generate(200, (i) => i % 256)));
      // Original offsets pointing into mdat (mdat starts right after ftyp at ftyp.length)
      final originalOffsets = [ftyp.length, ftyp.length + 50, ftyp.length + 100];
      final moov = _createMoovBoxWithStco(originalOffsets);

      // Construct MP4 with moov AT THE END: ftyp + mdat + moov
      final originalMp4 = Uint8List.fromList([...ftyp, ...mdat, ...moov]);
      final mp4File = File(p.join(tempDir.path, 'camera_recording.mp4'));
      await mp4File.writeAsBytes(originalMp4);

      final projector = await Mp4FastStartProjector.create(
        filePath: mp4File.path,
        fileSize: originalMp4.length,
      );

      expect(projector, isNotNull);
      expect(projector!.virtualSize, equals(originalMp4.length));

      // Virtual layout should be: ftyp (ftyp.length) + patchedMoov (moov.length) + mdat (mdat.length)
      final fullVirtualBytes = await projector.readSlice(0, projector.virtualSize);
      expect(fullVirtualBytes.length, equals(originalMp4.length));

      // Check ftyp at start
      expect(fullVirtualBytes.sublist(0, ftyp.length), equals(ftyp));

      // Check that moov is now at offset ftyp.length
      final moovInVirtual = fullVirtualBytes.sublist(ftyp.length, ftyp.length + moov.length);
      final moovType = String.fromCharCodes(moovInVirtual.sublist(4, 8));
      expect(moovType, equals('moov'));

      // Check that mdat is now after moov
      final mdatInVirtual = fullVirtualBytes.sublist(ftyp.length + moov.length);
      expect(String.fromCharCodes(mdatInVirtual.sublist(4, 8)), equals('mdat'));
      expect(mdatInVirtual.sublist(8), equals(mdat.sublist(8)));

      // Check that chunk offsets inside moov were shifted by moov.length
      // Find 'stco' in patched moov
      final stcoIdx = _findSublist(moovInVirtual, 'stco'.codeUnits);
      expect(stcoIdx, isNonNegative);

      final bdata = ByteData.sublistView(moovInVirtual);
      final entryCount = bdata.getUint32(stcoIdx + 8);
      expect(entryCount, equals(originalOffsets.length));

      for (var i = 0; i < originalOffsets.length; i++) {
        final patchedOffset = bdata.getUint32(stcoIdx + 12 + i * 4);
        expect(patchedOffset, equals(originalOffsets[i] + moov.length));
      }
    });

    test('TC-FS-04: MP4 with co64 (64-bit offsets) patches correctly', () async {
      final ftyp = _createBox('ftyp', Uint8List.fromList([1, 2, 3, 4]));
      final mdat = _createBox('mdat', Uint8List.fromList(List.generate(300, (i) => i % 256)));
      final originalOffsets = [ftyp.length + 10, ftyp.length + 100];
      final moov = _createMoovBoxWithCo64(originalOffsets);

      final originalMp4 = Uint8List.fromList([...ftyp, ...mdat, ...moov]);
      final mp4File = File(p.join(tempDir.path, 'large_64bit.mp4'));
      await mp4File.writeAsBytes(originalMp4);

      final projector = await Mp4FastStartProjector.create(
        filePath: mp4File.path,
        fileSize: originalMp4.length,
      );

      expect(projector, isNotNull);

      final virtualBytes = await projector!.readSlice(0, projector.virtualSize);
      final moovInVirtual = virtualBytes.sublist(ftyp.length, ftyp.length + moov.length);
      final co64Idx = _findSublist(moovInVirtual, 'co64'.codeUnits);
      expect(co64Idx, isNonNegative);

      final bdata = ByteData.sublistView(moovInVirtual);
      for (var i = 0; i < originalOffsets.length; i++) {
        final patchedOffset = bdata.getUint64(co64Idx + 12 + i * 8);
        expect(patchedOffset, equals(originalOffsets[i] + moov.length));
      }
    });

    test('TC-FS-05: RawStreamChunker integrates with Mp4FastStartProjector', () async {
      final ftyp = _createBox('ftyp', Uint8List.fromList([1, 2, 3, 4]));
      final mdat = _createBox('mdat', Uint8List.fromList(List.generate(500, (i) => (i * 3) % 256)));
      final moov = _createMoovBoxWithStco([ftyp.length]);

      final originalMp4 = Uint8List.fromList([...ftyp, ...mdat, ...moov]);
      final mp4File = File(p.join(tempDir.path, 'chunked_video.mp4'));
      await mp4File.writeAsBytes(originalMp4);

      // Create chunker with small chunk size (100 bytes)
      final chunker = await RawStreamChunker.create(
        filename: 'chunked_video.mp4',
        fileSize: originalMp4.length,
        filePath: mp4File.path,
        chunkSize: 100,
      );

      expect(chunker.isFastStartProjected, isTrue);

      // Part 1 should contain ftyp + moov at the very beginning!
      final part1 = await chunker.readPart(1);
      expect(part1.length, equals(100));
      expect(String.fromCharCodes(part1.sublist(4, 8)), equals('ftyp'));
      expect(String.fromCharCodes(part1.sublist(ftyp.length + 4, ftyp.length + 8)), equals('moov'));

      // Reconstruct all parts and verify total size matches original
      final allParts = <int>[];
      for (var p = 1; p <= chunker.partCount; p++) {
        allParts.addAll(await chunker.readPart(p));
      }
      expect(allParts.length, equals(originalMp4.length));
    });
  });
}

int _findSublist(Uint8List haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}
