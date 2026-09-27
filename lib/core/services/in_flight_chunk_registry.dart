/*
 * File: in_flight_chunk_registry.dart
 * Description: Thread-safe in-flight chunk download registry deduplicating concurrent Telegram requests and sharing packet streams.
 */

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import '../utils/app_logger.dart';

/// Represents an active network download task for a specific file chunk.
class InFlightChunkTask {
  /// File identifier.
  final String fileId;

  /// 0-indexed chunk part index.
  final int chunkIndex;

  /// Cancellation token governing the active network stream.
  final CancelToken cancelToken;

  final Completer<File?> _completionCompleter = Completer<File?>();
  final StreamController<List<int>> _streamController = StreamController<List<int>>.broadcast();
  int _bytesReceived = 0;
  bool _isDisposed = false;

  /// Future that completes with the committed [File] when fully cached to disk, or null if cancelled.
  Future<File?> get completionFuture => _completionCompleter.future;

  /// Active broadcast stream of downloaded byte packets as they arrive from the network.
  Stream<List<int>> get packetStream => _streamController.stream;

  /// Total bytes received so far.
  int get bytesReceived => _bytesReceived;

  /// Whether this task has finished (succeeded, failed, or cancelled).
  bool get isFinished => _completionCompleter.isCompleted;

  /// Creates an in-flight chunk download task.
  InFlightChunkTask({
    required this.fileId,
    required this.chunkIndex,
    CancelToken? cancelToken,
  }) : cancelToken = cancelToken ?? CancelToken();

  /// Adds a newly arrived byte packet and broadcasts to all active listeners.
  void addPacket(List<int> packet) {
    if (_isDisposed || _streamController.isClosed) return;
    _bytesReceived += packet.length;
    _streamController.add(packet);
  }

  /// Concludes packet emission and completes the task with the final committed [file].
  void complete(File? file) {
    if (_isDisposed) return;
    _isDisposed = true;
    if (!_streamController.isClosed) {
      _streamController.close();
    }
    if (!_completionCompleter.isCompleted) {
      _completionCompleter.complete(file);
    }
  }

  /// Signals an error on the stream and completes with error.
  void fail(Object error, [StackTrace? stackTrace]) {
    if (_isDisposed) return;
    _isDisposed = true;
    if (!_streamController.isClosed) {
      _streamController.addError(error, stackTrace);
      _streamController.close();
    }
    if (!_completionCompleter.isCompleted) {
      _completionCompleter.completeError(error, stackTrace);
    }
  }

  /// Cancels the in-flight download and cleans up listeners.
  void cancel([String reason = 'Cancelled']) {
    if (_isDisposed) return;
    cancelToken.cancel(reason);
    complete(null);
  }
}

/// Central registry coordinating in-flight video chunk downloads across pipelining and prefetching.
class InFlightChunkRegistry {
  InFlightChunkRegistry._();

  /// Singleton instance.
  static final InFlightChunkRegistry instance = InFlightChunkRegistry._();

  final Map<String, InFlightChunkTask> _tasks = {};

  static String _key(String fileId, int chunkIndex) => '$fileId:$chunkIndex';

  /// Returns the active in-flight task for [fileId] and [chunkIndex], if one exists.
  InFlightChunkTask? get(String fileId, int chunkIndex) {
    final task = _tasks[_key(fileId, chunkIndex)];
    if (task != null && task.isFinished) {
      _tasks.remove(_key(fileId, chunkIndex));
      return null;
    }
    return task;
  }

  /// Registers an active in-flight task for [fileId] and [chunkIndex].
  ///
  /// If a task already exists for this chunk, the existing task is returned to ensure deduplication.
  InFlightChunkTask register(
    String fileId,
    int chunkIndex, {
    CancelToken? cancelToken,
  }) {
    final k = _key(fileId, chunkIndex);
    final existing = _tasks[k];
    if (existing != null && !existing.isFinished) {
      AppLogger.i(
        '[DEDUP_HIT] Reusing in-flight download for $fileId chunk $chunkIndex',
        tag: 'InFlightChunkRegistry',
      );
      return existing;
    }

    final task = InFlightChunkTask(
      fileId: fileId,
      chunkIndex: chunkIndex,
      cancelToken: cancelToken,
    );
    _tasks[k] = task;

    task.completionFuture.whenComplete(() {
      if (_tasks[k] == task) {
        _tasks.remove(k);
      }
    });

    return task;
  }

  /// Unregisters an in-flight chunk task.
  void unregister(String fileId, int chunkIndex) {
    final k = _key(fileId, chunkIndex);
    final task = _tasks.remove(k);
    task?.cancel('Unregistered');
  }

  /// Cancels all in-flight chunk tasks for [fileId].
  void cancelForFile(String fileId) {
    final prefix = '$fileId:';
    final matchingKeys = _tasks.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in matchingKeys) {
      final task = _tasks.remove(k);
      task?.cancel('Cancelled for file $fileId');
    }
  }

  /// Cancels all active in-flight chunk tasks across all files.
  void cancelAll() {
    for (final task in _tasks.values) {
      task.cancel('Registry cancelAll');
    }
    _tasks.clear();
  }

  /// Clears tasks for testing without cancelling.
  void clearForTesting() => _tasks.clear();
}
