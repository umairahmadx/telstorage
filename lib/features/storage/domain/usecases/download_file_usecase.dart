/*
 * File: download_file_usecase.dart
 * Description: Component and logic definition for download_file_usecase.dart in TelStorage.
 */

import '../../../../core/errors/result.dart';
import '../../../../core/models/download_conflict_policy.dart';
import '../../../../core/models/file_record.dart';
import '../repositories/storage_repository_contract.dart';

class DownloadFileUseCase {
  final DownloadEnqueuer _repository;
  const DownloadFileUseCase(this._repository);

  Future<Result<void>> call(
    FileRecord file, {
    String? subpath,
    DownloadConflictPolicy policy = DownloadConflictPolicy.overwrite,
  }) async {
    return _repository.enqueueDownload(file, subpath: subpath, policy: policy);
  }
}
