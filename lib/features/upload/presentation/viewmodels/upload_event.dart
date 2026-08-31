/*
 * File: upload_event.dart
 * Description: Event hierarchy for upload operations and queue orchestration.
 */

import 'dart:typed_data';
import 'upload_task.dart';

/// Base abstract event for upload operations.
sealed class UploadEvent {}

/// Starts upload of a single file payload.
class StartUpload extends UploadEvent {
  /// File bytes.
  final Uint8List bytes;

  /// File name.
  final String name;

  /// Destination folder ID.
  final String? folderId;

  /// Constructs StartUpload event.
  StartUpload({required this.bytes, required this.name, this.folderId});
}

/// Appends a batch of UploadTasks to queue.
class AddUploads extends UploadEvent {
  /// List of upload tasks.
  final List<UploadTask> tasks;

  /// Constructs AddUploads event.
  AddUploads(this.tasks);
}

/// Cancels a queued upload task by ID.
class CancelUploadTask extends UploadEvent {
  /// Unique task identifier.
  final String taskId;

  /// Constructs CancelUploadTask event.
  CancelUploadTask(this.taskId);
}

/// Internal event triggering queue processing.
class ProcessNextUpload extends UploadEvent {}

/// Event emitted on upload progress tick.
class UploadProgressUpdated extends UploadEvent {
  /// Progress fraction (0.0 to 1.0).
  final double progress;

  /// Progress message text.
  final String status;

  /// Constructs UploadProgressUpdated event.
  UploadProgressUpdated(this.progress, this.status);
}

/// Event emitted when an upload completes.
class UploadCompleted extends UploadEvent {}

/// Event emitted when an upload fails.
class UploadFailed extends UploadEvent {
  /// Error message description.
  final String message;

  /// Associated file name.
  final String fileName;

  /// Constructs UploadFailed event.
  UploadFailed(this.message, {required this.fileName});
}

/// Resets upload queue to idle state.
class ResetUpload extends UploadEvent {}
