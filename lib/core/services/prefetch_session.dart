/*
 * File: prefetch_session.dart
 * Description: Data class and active state container for background video prefetching sessions.
 */

import 'dart:async';
import 'package:dio/dio.dart';
import '../models/chunk_info.dart';
import '../models/file_record.dart';

/// Encapsulates the runtime state of a background video prefetch sliding-window worker.
class PrefetchSession {
  /// Target file record being prefetched.
  final FileRecord record;

  /// Optional chunk metadata map.
  Map<int, ChunkInfo>? chunkMap;

  /// Current playback anchor chunk.
  int currentPlaybackChunk;

  /// Whether the session has been cancelled (e.g. on seek or player dispose).
  bool isCancelled = false;

  /// Set of chunk indices that are currently in-flight or successfully cached.
  final Set<int> inFlightOrCompleted = {};

  /// Current downloaded bytes for active chunks.
  final Map<int, int> inFlightBytes = {};

  /// Total expected bytes for active chunks.
  final Map<int, int> inFlightTotals = {};

  /// Active cancellation tokens for sliding-window background prefetch chunks.
  final Map<int, CancelToken> inFlightCancelTokens = {};

  /// Completer for the background sliding-window worker loop.
  Completer<void>? workerCompleter;

  /// Creates a prefetch session anchored at [currentPlaybackChunk].
  PrefetchSession({
    required this.record,
    required this.currentPlaybackChunk,
    this.chunkMap,
  });
}
