/*
 * File: upload_state.dart
 * Description: State hierarchy representing upload lifecycle, batch metrics, and network retry status.
 */

/// Base abstract state for upload lifecycle.
sealed class UploadState {}

/// Idle state when no uploads are active.
class UploadIdle extends UploadState {}

/// State representing an active upload in progress.
class UploadInProgress extends UploadState {
  /// Current progress fraction (0.0 to 1.0).
  final double progress;

  /// Textual description of progress stage.
  final String status;

  /// Name of file currently being uploaded.
  final String fileName;

  /// Number of completed tasks in current batch.
  final int completedCount;

  /// Total number of tasks in batch.
  final int totalCount;

  /// Constructs UploadInProgress state.
  UploadInProgress({
    required this.progress,
    required this.status,
    required this.fileName,
    this.completedCount = 0,
    this.totalCount = 1,
  });
}

/// State indicating batch upload completed successfully.
class UploadSuccess extends UploadState {
  /// Summary description of uploaded file(s).
  final String fileName;

  /// Constructs UploadSuccess state.
  UploadSuccess(this.fileName);
}

/// Global upload failure state.
class UploadError extends UploadState {
  /// Error message string.
  final String message;

  /// Constructs UploadError state.
  UploadError(this.message);
}

/// State representing single file failure within a batch.
class UploadSingleError extends UploadState {
  /// File name that failed.
  final String fileName;

  /// Error message.
  final String message;

  /// Constructs UploadSingleError state.
  UploadSingleError({required this.fileName, required this.message});
}

/// State indicating upload is paused awaiting internet reconnection.
class UploadWaitingForNetwork extends UploadState {
  /// File name paused on.
  final String fileName;

  /// Constructs UploadWaitingForNetwork state.
  UploadWaitingForNetwork(this.fileName);
}
