/*
 * File: zip_stream_chunker_test.dart
 * Description: Unit tests for ZipStreamChunker validating bit-exact ZIP parts reassembly and decoding.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/video_stream_server.dart';
import 'package:telstorage/core/utils/zip_stream_chunker.dart';

void main() {
  group('ZipStreamChunker Tests', () {
    test('TC-ZSC-01: Reassembles chunks into valid Zip archive matching original content (in-memory)', () async {
      const filename = 'test_sample.mp4';
      final payload = Uint8List.fromList(List.generate(50000, (i) => (i * 7) % 256));
      final hashInfo = ZipStreamChunker.hashAndCrcBytes(payload);

      // Use a small chunk size (10 KB) to ensure multi-part slicing across boundaries
      final chunker = ZipStreamChunker(
        filename: filename,
        fileSize: payload.length,
        crc32: hashInfo.crc32,
        bytes: payload,
        chunkSize: 10240,
      );

      expect(chunker.partCount, greaterThan(1));

      final assembledBuilder = BytesBuilder(copy: false);
      for (int i = 1; i <= chunker.partCount; i++) {
        final part = await chunker.readPart(i);
        expect(part.length, lessThanOrEqualTo(10240));
        assembledBuilder.add(part);
      }

      final assembledBytes = assembledBuilder.toBytes();
      expect(assembledBytes.length, chunker.totalZipSize);

      // Verify ZipDecoder decodes it without errors
      final decodedArchive = ZipDecoder().decodeBytes(assembledBytes);
      expect(decodedArchive.length, 1);
      expect(decodedArchive.first.name, filename);
      expect(decodedArchive.first.content, equals(payload));

      // Verify VideoStreamServer offset aligns precisely with local header
      final expectedHeaderOffset = VideoStreamServer.calculateHeaderOffset(filename, isZipped: true);
      expect(chunker.localHeader.length, expectedHeaderOffset);
      expect(assembledBytes.sublist(expectedHeaderOffset, expectedHeaderOffset + payload.length), equals(payload));
    });

    test('TC-ZSC-02: Reassembles chunks from disk file into valid Zip archive', () async {
      final tempDir = Directory.systemTemp.createTempSync('zsc_test_');
      final tempFile = File('${tempDir.path}/test_video.mkv');
      final payload = Uint8List.fromList(List.generate(100000, (i) => (i * 13) % 256));
      tempFile.writeAsBytesSync(payload);

      try {
        final hashInfo = await ZipStreamChunker.hashAndCrcFile(tempFile.path);
        expect(hashInfo.fileSize, payload.length);

        final chunker = ZipStreamChunker(
          filename: 'test_video.mkv',
          fileSize: hashInfo.fileSize,
          crc32: hashInfo.crc32,
          filePath: tempFile.path,
          chunkSize: 16384, // 16 KB chunks
        );

        final assembledBuilder = BytesBuilder(copy: false);
        for (int i = 1; i <= chunker.partCount; i++) {
          final part = await chunker.readPart(i);
          expect(part.length, lessThanOrEqualTo(16384));
          assembledBuilder.add(part);
        }

        final assembledBytes = assembledBuilder.toBytes();
        final decodedArchive = ZipDecoder().decodeBytes(assembledBytes);
        expect(decodedArchive.length, 1);
        expect(decodedArchive.first.name, 'test_video.mkv');
        expect(decodedArchive.first.content, equals(payload));
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('TC-ZSC-03: Throws RangeError on invalid part index', () async {
      final chunker = ZipStreamChunker(
        filename: 'file.txt',
        fileSize: 100,
        crc32: 12345,
        bytes: Uint8List(100),
      );

      expect(() => chunker.readPart(0), throwsRangeError);
      expect(() => chunker.readPart(chunker.partCount + 1), throwsRangeError);
    });
  });
}
