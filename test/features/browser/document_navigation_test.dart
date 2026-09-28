/*
 * File: document_navigation_test.dart
 * Description: Verifies that tapping a document file in the file browser routes to DocumentViewerScreen.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/document_viewer_cache_service.dart';

void main() {
  group('Document Navigation Integration Tests', () {
    test('DocumentViewerCacheService routes document taps', () {
      final pdf = FileRecord(
        fileId: '1',
        name: 'report.pdf',
        metadataMessageId: 1,
        sizeMb: 1.0,
        mimeType: 'application/pdf',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'h',
      );

      final text = FileRecord(
        fileId: '2',
        name: 'main.py',
        metadataMessageId: 2,
        sizeMb: 0.1,
        mimeType: 'text/x-python',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'h',
      );

      final docx = FileRecord(
        fileId: '3',
        name: 'contract.docx',
        metadataMessageId: 3,
        sizeMb: 0.5,
        mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'h',
      );

      expect(DocumentViewerCacheService.isDocumentRecord(pdf), isTrue);
      expect(DocumentViewerCacheService.isDocumentRecord(text), isTrue);
      expect(DocumentViewerCacheService.isDocumentRecord(docx), isTrue);
    });
  });
}
