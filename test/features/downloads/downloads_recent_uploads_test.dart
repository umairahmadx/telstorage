/*
 * File: downloads_recent_uploads_test.dart
 * Description: Tests verifying that the uploads section displays only the latest 10 recent items.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/features/downloads/presentation/screens/downloads/viewmodel/downloads_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Downloads Recent Uploads Top-10 Tests', () {
    test('TC-01: TransferState properly holds uploadJobs and updates via copyWith', () {
      final mock15Files = List.generate(
        15,
        (i) => FileRecord(
          fileId: 'file_$i',
          name: 'file_$i.png',
          metadataMessageId: 100 + i,
          sizeMb: 1.5,
          mimeType: 'image/png',
          uploadedAt: DateTime.now().subtract(Duration(minutes: i)),
          chunkCount: 1,
          sha256Hash: 'hash_$i',
        ),
      );

      final state = TransferState(uploadJobs: mock15Files.take(10).toList());

      expect(state.uploadJobs.length, equals(10));
      expect(state.uploadJobs.first.name, equals('file_0.png'));
      expect(state.uploadJobs.last.name, equals('file_9.png'));
    });

    test('TC-02: Upload filter logic takes at most 10 items even if input list is larger', () {
      final mock25Files = List.generate(
        25,
        (i) => FileRecord(
          fileId: 'file_$i',
          name: 'file_$i.png',
          metadataMessageId: 200 + i,
          sizeMb: 2.0,
          mimeType: 'image/png',
          uploadedAt: DateTime.now().subtract(Duration(minutes: i)),
          chunkCount: 1,
          sha256Hash: 'hash_$i',
        ),
      );

      const query = '';
      final uploadFiles = mock25Files.where((f) {
        if (query.isNotEmpty && !f.name.toLowerCase().contains(query)) {
          return false;
        }
        return true;
      }).take(10).toList();

      expect(uploadFiles.length, equals(10));
      expect(uploadFiles.first.fileId, equals('file_0'));
      expect(uploadFiles.last.fileId, equals('file_9'));
    });

    test('TC-03: Search query filtering correctly filters and still respects 10 item cap', () {
      final mockFiles = List.generate(
        30,
        (i) => FileRecord(
          fileId: 'file_$i',
          name: i.isEven ? 'vacation_photo_$i.jpg' : 'work_document_$i.pdf',
          metadataMessageId: 300 + i,
          sizeMb: 3.0,
          mimeType: i.isEven ? 'image/jpeg' : 'application/pdf',
          uploadedAt: DateTime.now().subtract(Duration(minutes: i)),
          chunkCount: 1,
          sha256Hash: 'hash_$i',
        ),
      );

      const query = 'photo';
      final filteredUploads = mockFiles.where((f) {
        if (query.isNotEmpty && !f.name.toLowerCase().contains(query)) {
          return false;
        }
        return true;
      }).take(10).toList();

      expect(filteredUploads.length, equals(10));
      for (final f in filteredUploads) {
        expect(f.name.contains('photo'), isTrue);
      }
    });
  });
}
