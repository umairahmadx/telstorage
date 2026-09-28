/*
 * File: document_viewer_cache_service_test.dart
 * Description: Unit tests for DocumentViewerCacheService format detection and cache operations.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/document_viewer_cache_service.dart';

void main() {
  group('DocumentViewerCacheService Format Detection', () {
    test('isPdfRecord identifies .pdf files correctly', () {
      final pdf = FileRecord(
        fileId: '1',
        name: 'contract.pdf',
        metadataMessageId: 1,
        sizeMb: 1.2,
        mimeType: 'application/pdf',
        uploadedAt: DateTime.now(),
        chunkCount: 1,
        sha256Hash: 'abc',
      );
      expect(DocumentViewerCacheService.isPdfRecord(pdf), isTrue);
      expect(DocumentViewerCacheService.isDocumentRecord(pdf), isTrue);
      expect(DocumentViewerCacheService.isTextRecord(pdf), isFalse);
      expect(DocumentViewerCacheService.isOfficeRecord(pdf), isFalse);
    });

    test('isTextRecord identifies code and text files correctly', () {
      final textFiles = [
        'main.dart',
        'script.py',
        'app.js',
        'index.ts',
        'notes.txt',
        'README.md',
        'data.json',
        'config.yaml',
        'schema.sql',
        'run.sh',
      ];

      for (final name in textFiles) {
        final rec = FileRecord(
          fileId: name,
          name: name,
          metadataMessageId: 1,
          sizeMb: 0.1,
          mimeType: 'text/plain',
          uploadedAt: DateTime.now(),
          chunkCount: 1,
          sha256Hash: 'abc',
        );
        expect(DocumentViewerCacheService.isTextRecord(rec), isTrue,
            reason: '$name should be recognized as text/code');
        expect(DocumentViewerCacheService.isDocumentRecord(rec), isTrue);
        expect(DocumentViewerCacheService.isPdfRecord(rec), isFalse);
      }
    });

    test('isOfficeRecord identifies Office document formats', () {
      final officeFiles = [
        'report.docx',
        'sheets.xlsx',
        'slides.pptx',
        'legacy.doc',
        'data.xls',
        'deck.ppt',
        'doc.odt',
      ];

      for (final name in officeFiles) {
        final rec = FileRecord(
          fileId: name,
          name: name,
          metadataMessageId: 1,
          sizeMb: 2.0,
          mimeType: 'application/octet-stream',
          uploadedAt: DateTime.now(),
          chunkCount: 1,
          sha256Hash: 'abc',
        );
        expect(DocumentViewerCacheService.isOfficeRecord(rec), isTrue,
            reason: '$name should be recognized as office');
        expect(DocumentViewerCacheService.isDocumentRecord(rec), isTrue);
      }
    });

    test('Non-document files return false for all document checks', () {
      final nonDocs = ['song.mp3', 'video.mp4', 'pic.png', 'archive.zip'];
      for (final name in nonDocs) {
        final rec = FileRecord(
          fileId: name,
          name: name,
          metadataMessageId: 1,
          sizeMb: 5.0,
          mimeType: 'application/octet-stream',
          uploadedAt: DateTime.now(),
          chunkCount: 1,
          sha256Hash: 'abc',
        );
        expect(DocumentViewerCacheService.isDocumentRecord(rec), isFalse);
      }
    });
  });
}
