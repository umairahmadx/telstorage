/*
 * File: interface_segregation_test.dart
 * Description: Interface segregation tests verifying use cases depend on minimal interface contracts.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/errors/result.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';
import 'package:telstorage/features/storage/domain/usecases/download_file_usecase.dart';
import 'package:telstorage/features/storage/domain/usecases/generate_web_share_usecase.dart';

class DownloadOnlyFake implements DownloadEnqueuer {
  @override
  Future<Result<void>> enqueueDownload(FileRecord file) async =>
      const Success(null);
}

class WebShareOnlyFake implements WebShareEnqueuer {
  @override
  Future<Result<void>> enqueueWebShare(
    FileRecord file, {
    String? password,
    int? expiryDays,
    String? vanitySlug,
  }) async =>
      const Success(null);
}

void main() {
  test('download use case depends only on DownloadEnqueuer', () async {
    final file = FileRecord(
      fileId: 'file-1',
      name: 'document.pdf',
      metadataMessageId: 1,
      sizeMb: 1,
      mimeType: 'application/pdf',
      uploadedAt: DateTime(2026),
      chunkCount: 1,
      sha256Hash: 'hash',
    );

    final result = await DownloadFileUseCase(DownloadOnlyFake())(file);

    expect(result, isA<Success<void>>());
  });

  test('web-share use case depends only on WebShareEnqueuer', () async {
    final file = FileRecord(
      fileId: 'file-1',
      name: 'document.pdf',
      metadataMessageId: 1,
      sizeMb: 1,
      mimeType: 'application/pdf',
      uploadedAt: DateTime(2026),
      chunkCount: 1,
      sha256Hash: 'hash',
    );

    final result = await GenerateWebShareUseCase(WebShareOnlyFake())(
      GenerateWebShareParams(file: file, expiryDays: 7),
    );

    expect(result, isA<Success<void>>());
  });
}
