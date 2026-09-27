/*
 * File: video_buffer_projector.dart
 * Description: Calculates merged buffered duration ranges from disk chunks and in-flight streaming byte progress.
 */

import '../../../../../../core/models/video_stream_models.dart';

/// Helper computing merged duration ranges by projecting downloaded and in-flight chunk ranges to video timeline.
class VideoBufferProjector {
  const VideoBufferProjector._();

  /// Computes merged continuous buffered duration ranges.
  static List<DurationRange> computeMergedBuffered({
    required Duration duration,
    required int totalChunks,
    required List<DurationRange> playerBuffered,
    required Set<int> cachedChunks,
    required Map<int, double> inFlightFractions,
  }) {
    if (duration <= Duration.zero) {
      return playerBuffered;
    }

    final totalMs = duration.inMilliseconds;
    final chunksCount = totalChunks > 0 ? totalChunks : 1;
    final rawRanges = <DurationRange>[...playerBuffered];

    for (final idx in cachedChunks) {
      final startMs = (totalMs * idx / chunksCount).round();
      final endMs = (totalMs * (idx + 1) / chunksCount).round().clamp(0, totalMs);
      rawRanges.add(DurationRange(
        Duration(milliseconds: startMs),
        Duration(milliseconds: endMs),
      ));
    }

    inFlightFractions.forEach((chunkIdx, fraction) {
      if (!cachedChunks.contains(chunkIdx) && fraction > 0) {
        final startMs = (totalMs * chunkIdx / chunksCount).round();
        final endMs = (totalMs * (chunkIdx + fraction) / chunksCount).round().clamp(0, totalMs);
        if (endMs > startMs) {
          rawRanges.add(DurationRange(
            Duration(milliseconds: startMs),
            Duration(milliseconds: endMs),
          ));
        }
      }
    });

    if (rawRanges.isEmpty) return const [];

    rawRanges.sort((a, b) => a.start.compareTo(b.start));

    final merged = <DurationRange>[rawRanges.first];
    for (int i = 1; i < rawRanges.length; i++) {
      final current = rawRanges[i];
      final last = merged.last;
      if (current.start <= last.end) {
        if (current.end > last.end) {
          merged[merged.length - 1] = DurationRange(last.start, current.end);
        }
      } else {
        merged.add(current);
      }
    }
    return merged;
  }
}
