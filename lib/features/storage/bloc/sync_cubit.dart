import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/utils/app_logger.dart';

// ── States ────────────────────────────────────────────────────────────────────

sealed class SyncState {}

class SyncInitial extends SyncState {}

class SyncInProgress extends SyncState {
  final double progress;
  final String status;
  SyncInProgress({required this.progress, required this.status});
}

class SyncSuccess extends SyncState {
  final SyncResult result;
  SyncSuccess(this.result);
}

class SyncError extends SyncState {
  final String message;
  SyncError(this.message);
}

// ── Cubit ─────────────────────────────────────────────────────────────────────

class SyncCubit extends Cubit<SyncState> {
  SyncCubit() : super(SyncInitial());

  Future<void> sync() async {
    if (state is SyncInProgress) return; // Prevent double-trigger
    if (!ServiceLocator.instance.isInitialized) {
      emit(SyncError('Not logged in'));
      return;
    }

    emit(SyncInProgress(progress: 0.0, status: 'Connecting...'));
    try {
      final result = await ServiceLocator.instance.syncService.syncFromTelegram(
        onProgress: (progress, status) {
          if (!isClosed) {
            emit(SyncInProgress(progress: progress, status: status));
          }
        },
      );
      AppLogger.i('SyncCubit: sync complete — ${result.added} added, ${result.removed} removed', tag: 'SyncCubit');
      emit(SyncSuccess(result));
    } catch (e) {
      AppLogger.e('SyncCubit: sync failed', tag: 'SyncCubit', error: e);
      emit(SyncError(e.toString()));
    }
  }

  void reset() => emit(SyncInitial());
}
