/*
 * File: generate_web_share_usecase.dart
 * Description: Component and logic definition for generate_web_share_usecase.dart in TelStorage.
 */

import '../../../../core/errors/result.dart';
import '../../../../core/models/file_record.dart';
import '../repositories/storage_repository_contract.dart';

class GenerateWebShareParams {
  final FileRecord file;
  final String? password;
  final int? expiryDays;
  final String? vanitySlug;

  const GenerateWebShareParams({
    required this.file,
    this.password,
    this.expiryDays,
    this.vanitySlug,
  });
}

class GenerateWebShareUseCase {
  final WebShareEnqueuer _repository;
  const GenerateWebShareUseCase(this._repository);

  Future<Result<void>> call(GenerateWebShareParams params) async {
    try {
      await _repository.enqueueWebShare(
        params.file,
        password: params.password,
        expiryDays: params.expiryDays,
        vanitySlug: params.vanitySlug,
      );
      return const Success(null);
    } catch (e) {
      return Failure(UnknownFailure(e.toString(), e));
    }
  }
}
