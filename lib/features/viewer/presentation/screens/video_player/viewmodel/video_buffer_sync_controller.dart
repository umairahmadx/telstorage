/*
 * File: video_buffer_sync_controller.dart
 * Description: Manages chunk cache and in-flight prefetch progress synchronization with video buffer timeline.
 */

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../../../core/services/video_chunk_cache_manager.dart';
import '../../../../../../core/services/video_stream_server.dart';
import 'video_buffer_projector.dart';

/// Coordinates live disk-cached chunks and Telegram prefetch progress with timeline buffer projections.
class VideoBufferSyncController {
  Set<int> _cachedChunks = const {};
  List<DurationRange> _mergedBuffered = const [];
  bool _isListening = false;
  String? _activeFileId;
  int _totalChunks = 1;

  VoidCallback? onUpdate;

  Set<int> get cachedChunks => _cachedChunks;
  List<DurationRange> get mergedBuffered => _mergedBuffered;

  Map<int, double>? _mockInFlightFractions;
  int? _mockInFlightBytes;

  /// Attaches listeners for chunk caching and background prefetch progress.
  void attach({
    required String fileId,
    required int totalChunks,
    required VoidCallback onUpdateCallback,
  }) {
    _activeFileId = fileId;
    _totalChunks = totalChunks;
    onUpdate = onUpdateCallback;

    if (!_isListening) {
      _isListening = true;
      VideoChunkCacheManager.instance.chunkChangeNotifier.addListener(_onChunkCacheChanged);
      try {
        VideoStreamServer.instance.prefetchCoordinator.prefetchProgressNotifier
            .addListener(_onPrefetchProgressChanged);
      } catch (_) {}
    }
  }

  Future<void> _onChunkCacheChanged() async {
    final fileId = _activeFileId;
    if (fileId != null) {
      final indices = await VideoChunkCacheManager.instance.getCachedChunkIndices(fileId);
      if (_activeFileId == fileId) {
        _cachedChunks = indices;
      }
    }
    onUpdate?.call();
  }

  void _onPrefetchProgressChanged() {
    onUpdate?.call();
  }

  /// Refreshes cached chunks for [fileId] from disk cache and recomputes merged buffer ranges.
  Future<void> refresh(String fileId, Duration duration, List<DurationRange> playerBuffered) async {
    final indices = await VideoChunkCacheManager.instance.getCachedChunkIndices(fileId);
    if (_activeFileId != fileId) return;
    _cachedChunks = indices;
    compute(duration, playerBuffered);
  }

  /// Recalculates [mergedBuffered] ranges using current player and disk cache states.
  void compute(Duration duration, List<DurationRange> playerBuffered) {
    _mergedBuffered = VideoBufferProjector.computeMergedBuffered(
      duration: duration,
      totalChunks: _totalChunks,
      playerBuffered: playerBuffered,
      cachedChunks: _cachedChunks,
      inFlightFractions: getInFlightFractions(_activeFileId),
    );
  }

  /// Calculates total cached megabytes including partial in-flight chunks.
  double computeCachedMb(double? sizeMb) {
    final bytes = getInFlightBytes(_activeFileId);
    final total = _cachedChunks.length * 19.0 + (bytes / 1048576);
    return total.clamp(0.0, (sizeMb != null && sizeMb > 0) ? sizeMb : double.infinity);
  }

  /// Returns in-flight fraction progress for chunks of [fileId].
  Map<int, double> getInFlightFractions(String? fileId) {
    if (_mockInFlightFractions != null) return _mockInFlightFractions!;
    if (fileId == null) return const {};
    try {
      return VideoStreamServer.instance.prefetchCoordinator.getInFlightFractions(fileId);
    } catch (_) {
      return const {};
    }
  }

  /// Returns in-flight downloaded bytes across chunks of [fileId].
  int getInFlightBytes(String? fileId) {
    if (_mockInFlightBytes != null) return _mockInFlightBytes!;
    if (fileId == null) return 0;
    try {
      return VideoStreamServer.instance.prefetchCoordinator.getInFlightBytes(fileId);
    } catch (_) {
      return 0;
    }
  }

  /// Sets mock in-flight prefetch progress for unit testing.
  void setMockInFlightProgress({required Map<int, double> fractions, required int bytes}) {
    _mockInFlightFractions = fractions;
    _mockInFlightBytes = bytes;
  }

  /// Sets mock cached chunks for unit tests.
  void setMockCachedChunks(Set<int> chunks) {
    _cachedChunks = chunks;
  }

  /// Resets state and detaches listeners.
  void reset() {
    _cachedChunks = const {};
    _mergedBuffered = const [];
  }

  /// Disposes listeners.
  void dispose() {
    if (_isListening) {
      VideoChunkCacheManager.instance.chunkChangeNotifier.removeListener(_onChunkCacheChanged);
      try {
        VideoStreamServer.instance.prefetchCoordinator.prefetchProgressNotifier
            .removeListener(_onPrefetchProgressChanged);
      } catch (_) {}
      _isListening = false;
    }
    _activeFileId = null;
    onUpdate = null;
    reset();
  }
}
