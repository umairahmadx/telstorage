import '../../../../core/errors/result.dart';
import '../../../../core/models/file_record.dart';
import '../repositories/storage_repository_contract.dart';

class DownloadFileUseCase {
  final DownloadEnqueuer _repository;
  const DownloadFileUseCase(this._repository);

  Future<Result<void>> call(FileRecord file) async {
    return _repository.enqueueDownload(file);
  }
}
