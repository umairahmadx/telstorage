/*
 * File: video_drag_scrubber.dart
 * Description: Viewport drag-scrubbing state and delta calculations for video player timeline.
 */

import 'dart:math';

/// Encapsulates viewport horizontal drag-scrubbing math and state.
class VideoDragScrubber {
  bool _isDragging = false;
  Duration _dragTarget = Duration.zero;
  Duration _dragDelta = Duration.zero;
  Duration _dragOrigin = Duration.zero;
  double _accumulatedDeltaSec = 0.0;

  bool get isDragging => _isDragging;
  Duration get dragTarget => _dragTarget;
  Duration get dragDelta => _dragDelta;
  Duration get dragOrigin => _dragOrigin;

  /// Starts a drag scrub operation anchored at [currentPosition].
  void start(Duration currentPosition) {
    _isDragging = true;
    _dragOrigin = currentPosition;
    _accumulatedDeltaSec = 0.0;
    _dragDelta = Duration.zero;
    _dragTarget = currentPosition;
  }

  /// Updates the target scrub duration based on touch/mouse [deltaPixels] relative to [totalWidth].
  ///
  /// Returns `true` if state changed and a UI notify is needed.
  bool update(double deltaPixels, double totalWidth, Duration duration) {
    if (!_isDragging || totalWidth <= 0) return false;
    final maxSec = duration.inSeconds > 0 ? min(120.0, duration.inSeconds.toDouble()) : 120.0;
    _accumulatedDeltaSec += (deltaPixels / totalWidth) * maxSec;
    _dragDelta = Duration(milliseconds: (_accumulatedDeltaSec * 1000).round());
    final targetMs = (_dragOrigin.inMilliseconds + _dragDelta.inMilliseconds)
        .clamp(0, duration.inMilliseconds > 0 ? duration.inMilliseconds : 86400000);
    _dragTarget = Duration(milliseconds: targetMs);
    return true;
  }

  /// Concludes the drag scrubbing session and returns the final target duration to seek to.
  Duration end() {
    final finalTarget = _dragTarget;
    _isDragging = false;
    _dragDelta = Duration.zero;
    _accumulatedDeltaSec = 0.0;
    return finalTarget;
  }
}
