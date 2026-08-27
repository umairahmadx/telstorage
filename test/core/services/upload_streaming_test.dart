/*
 * File: upload_streaming_test.dart
 * Description: Unit tests verifying zero-copy byte view chunking for memory optimization in UploadService.
 */

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/upload_service.dart';

void main() {
  group('UploadService Zero-Copy Chunking Tests', () {
    test(
        'TC-01: splitBytesZeroCopy creates view slices sharing underlying ByteBuffer without heap duplication',
        () {
      final sourceBytes = Uint8List.fromList(List.generate(100, (i) => i));
      const partSize = 30;

      final chunks = UploadService.splitBytesZeroCopy(sourceBytes, partSize);

      expect(chunks.length, equals(4));
      expect(chunks[0].length, equals(30));
      expect(chunks[1].length, equals(30));
      expect(chunks[2].length, equals(30));
      expect(chunks[3].length, equals(10));

      // Assert zero-copy view identity: chunks must point to the identical ByteBuffer
      expect(chunks[0].buffer, equals(sourceBytes.buffer));
      expect(chunks[1].buffer, equals(sourceBytes.buffer));
      expect(chunks[2].buffer, equals(sourceBytes.buffer));
      expect(chunks[3].buffer, equals(sourceBytes.buffer));

      // Assert offset alignment
      expect(chunks[0].offsetInBytes, equals(0));
      expect(chunks[1].offsetInBytes, equals(30));
      expect(chunks[2].offsetInBytes, equals(60));
      expect(chunks[3].offsetInBytes, equals(90));
    });
  });
}
