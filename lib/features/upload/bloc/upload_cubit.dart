import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/utils/app_logger.dart';

// ── States ────────────────────────────────────────────────────────────────────

sealed class UploadState {}

class UploadIdle extends UploadState {}

class UploadInProgress extends UploadState {
  final double progress;
  final String status;
  final String fileName;
  UploadInProgress({
    required this.progress,
    required this.status,
    required this.fileName,
  });
}

class UploadSuccess extends UploadState {
  final String fileName;
  UploadSuccess(this.fileName);
}

class UploadError extends UploadState {
  final String message;
  UploadError(this.message);
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class UploadCubit extends Cubit<UploadState> {
  UploadCubit() : super(UploadIdle());

  Future<void> upload({
    required Uint8List bytes,
    required String name,
    String? folderId,
  }) async {
    if (state is UploadInProgress) return;
    if (!ServiceLocator.instance.isInitialized) {
      emit(UploadError('Not logged in'));
      return;
    }

    emit(UploadInProgress(
        progress: 0.0, status: 'Preparing...', fileName: name));
    try {
      await ServiceLocator.instance.uploadService.uploadFile(
        bytes,
        name,
        folderId,
        (progress, status) {
          if (!isClosed) {
            emit(UploadInProgress(
                progress: progress, status: status, fileName: name));
          }
        },
      );
      AppLogger.i('UploadCubit: $name uploaded successfully',
          tag: 'UploadCubit');
      emit(UploadSuccess(name));
    } catch (e) {
      AppLogger.e('UploadCubit: upload failed', tag: 'UploadCubit', error: e);
      emit(UploadError(e.toString()));
    }
  }

  void reset() => emit(UploadIdle());
}
