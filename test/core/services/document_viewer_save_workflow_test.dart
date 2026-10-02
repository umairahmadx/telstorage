/*
 * File: document_viewer_save_workflow_test.dart
 * Description: Verifies edited-document save ordering so a failed save never deletes the previous copy.
 */

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/services/document_viewer_cache_service.dart';
import 'package:telstorage/core/services/hive_service.dart';
import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/core/services/upload_service.dart';

/// Minimal upload stand-in returning a fixed new file id.
class _FakeUploadService extends Fake implements UploadService {
  _FakeUploadService(this.newFileId);

  final String newFileId;
  int calls = 0;

  @override
  Future<Result<Map<String, dynamic>>> uploadFile(
    Uint8List? bytes,
    String name,
    String? folderId,
    Function(double progress, String status) onProgress, {
    String? filePath,
    int? fileLength,
    bool skipGlobalMetadataUpdate = false,
    String? taskId,
    String? precomputedHash,
    Uint8List? precomputedThumbnailBytes,
    String? thumbnailExtension,
  }) async {
    calls++;
    return Success({'file_id': newFileId});
  }
}

/// Hive stand-in whose [getFile] is controllable, recording deletions.
class _FakeHiveService extends Fake implements HiveService {
  /// Record returned by [getFile] (null simulates an un-indexed upload).
  FileRecord? record;
  final List<String> deletedIds = [];

  @override
  FileRecord? getFile(String fileId) => record;

  @override
  Future<void> deleteFile(String fileId) async => deletedIds.add(fileId);
}

FileRecord _record(String id) => FileRecord(
      fileId: id,
      name: 'notes.dart',
      metadataMessageId: 1,
      sizeMb: 0.1,
      mimeType: 'text/plain',
      uploadedAt: DateTime.now(),
      chunkCount: 1,
      sha256Hash: 'hash_$id',
    );

void main() {
  late _FakeUploadService fakeUpload;
  late _FakeHiveService fakeHive;

  setUp(() {
    fakeUpload = _FakeUploadService('new_id');
    fakeHive = _FakeHiveService();
    ServiceLocator.instance.setUploadServiceForTesting(fakeUpload);
    ServiceLocator.instance.setHiveForTesting(fakeHive);
  });

  group('DocumentViewerCacheService save ordering', () {
    test('keeps the old record when the new upload is not indexed', () async {
      final old = _record('old_id');

      final result = await DocumentViewerCacheService.instance
          .saveEditedFile(old, 'edited content');

      expect(fakeUpload.calls, 1);
      expect(result, isA<Failure<FileRecord>>(),
          reason: 'An un-indexed upload must be reported as a failure');
      expect(fakeHive.deletedIds, isEmpty,
          reason: 'The superseded record must never be deleted before the new '
              'upload is durably indexed');
    });
  });
}