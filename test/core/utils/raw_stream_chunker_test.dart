/*
 * File: raw_stream_chunker_test.dart
 * Description: Unit tests for RawStreamChunker validating zero-wrapper raw partitioning and streaming SHA-256.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telstorage/core/utils/raw_stream_chunker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('raw_chunker_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('RawStreamChunker In-Memory Slicing Tests', () {
    test('TC-01: Empty 0-byte payload yields 1 empty part and correct naming', () async {
      final chunker = RawStreamChunker(
        filename: 'empty.txt',
        fileSize: 0,
        bytes: Uint8List(0),
        chunkSize: 1024,
      );

      expect(chunker.partCount, 1);
      expect(chunker.getPartName(1), 'empty.txt');

      final part1 = await chunker.readPart(1);
      expect(part1, isEmpty);
    });

    test('TC-02: Small payload smaller than chunk size yields 1 single part', () async {
      final data = Uint8List.fromList(List.generate(500, (i) => i % 256));
      final chunker = RawStreamChunker(
        filename: 'document.pdf',
        fileSize: data.length,
        bytes: data,
        chunkSize: 1024,
      );

      expect(chunker.partCount, 1);
      expect(chunker.getPartName(1), 'document.pdf');

      final part1 = await chunker.readPart(1);
      expect(part1, equals(data));
    });

    test('TC-03: Multi-part payload partitions accurately into .001, .002 parts', () async {
      const chunkSize = 1000;
      const totalBytes = 2500;
      final data = Uint8List.fromList(List.generate(totalBytes, (i) => (i * 7) % 256));

      final chunker = RawStreamChunker(
        filename: 'movie.mp4',
        fileSize: totalBytes,
        bytes: data,
        chunkSize: chunkSize,
      );

      expect(chunker.partCount, 3);
      expect(chunker.getPartName(1), 'movie.mp4.001');
      expect(chunker.getPartName(2), 'movie.mp4.002');
      expect(chunker.getPartName(3), 'movie.mp4.003');

      final part1 = await chunker.readPart(1);
      final part2 = await chunker.readPart(2);
      final part3 = await chunker.readPart(3);

      expect(part1.length, 1000);
      expect(part2.length, 1000);
      expect(part3.length, 500);

      // Verify concatenating all parts produces the exact original payload
      final reconstructed = Uint8List(totalBytes);
      reconstructed.setRange(0, 1000, part1);
      reconstructed.setRange(1000, 2000, part2);
      reconstructed.setRange(2000, 2500, part3);

      expect(reconstructed, equals(data));
      expect(sha256.convert(reconstructed).toString(), sha256.convert(data).toString());
    });

    test('TC-04: Exact multiple of chunk size does not create extra empty trailing part', () async {
      const chunkSize = 512;
      const totalBytes = 1024; // Exactly 2 * chunkSize
      final data = Uint8List.fromList(List.generate(totalBytes, (i) => i % 256));

      final chunker = RawStreamChunker(
        filename: 'archive.tar',
        fileSize: totalBytes,
        bytes: data,
        chunkSize: chunkSize,
      );

      expect(chunker.partCount, 2);
      expect(chunker.getPartName(1), 'archive.tar.001');
      expect(chunker.getPartName(2), 'archive.tar.002');

      final p1 = await chunker.readPart(1);
      final p2 = await chunker.readPart(2);
      expect(p1.length, 512);
      expect(p2.length, 512);
    });

    test('TC-05: Out of bounds partIndex throws RangeError', () async {
      final data = Uint8List(100);
      final chunker = RawStreamChunker(
        filename: 'test.dat',
        fileSize: data.length,
        bytes: data,
        chunkSize: 50,
      );

      expect(chunker.partCount, 2);
      expect(() => chunker.readPart(0), throwsRangeError);
      expect(() => chunker.readPart(3), throwsRangeError);
    });
  });

  group('RawStreamChunker Disk Streaming & Hashing Tests', () {
    test('TC-06: Streams directly from disk file without loading entire file into memory', () async {
      final filePath = p.join(tempDir.path, 'large_sample.bin');
      const totalBytes = 5 * 1024; // 5 KB
      final fileData = Uint8List.fromList(List.generate(totalBytes, (i) => (i * 13) % 256));
      await File(filePath).writeAsBytes(fileData);

      const chunkSize = 2048; // 2 KB chunks -> 3 parts (2048, 2048, 1024)
      final chunker = RawStreamChunker(
        filename: 'large_sample.bin',
        fileSize: totalBytes,
        filePath: filePath,
        chunkSize: chunkSize,
      );

      expect(chunker.partCount, 3);
      final part1 = await chunker.readPart(1);
      final part2 = await chunker.readPart(2);
      final part3 = await chunker.readPart(3);

      expect(part1.length, 2048);
      expect(part2.length, 2048);
      expect(part3.length, 1024);

      final combined = [...part1, ...part2, ...part3];
      expect(combined, equals(fileData));

      // Check streaming hashFile
      final hashResult = await RawStreamChunker.hashFile(filePath);
      expect(hashResult.fileSize, totalBytes);
      expect(hashResult.sha256, sha256.convert(fileData).toString());
    });
  });
}
