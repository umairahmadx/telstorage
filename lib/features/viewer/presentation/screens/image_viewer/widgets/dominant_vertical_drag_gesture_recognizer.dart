/*
 * File: dominant_vertical_drag_gesture_recognizer.dart
 * Description: VerticalDragGestureRecognizer subclass that yields to horizontal swipes to eliminate PageView conflict.
 */

import 'package:flutter/gestures.dart';

/// A [VerticalDragGestureRecognizer] that yields immediately if the pointer's
/// horizontal movement is dominant, ensuring that natural diagonal thumb swipes
/// never steal gestures from a horizontal [PageView].
class DominantVerticalDragGestureRecognizer
    extends VerticalDragGestureRecognizer {
  /// Constructs a [DominantVerticalDragGestureRecognizer].
  DominantVerticalDragGestureRecognizer({
    super.debugOwner,
    super.supportedDevices,
    super.allowedButtonsFilter,
  });

  Offset _startPosition = Offset.zero;
  bool _rejectedByHorizontal = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _startPosition = event.position;
    _rejectedByHorizontal = false;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && !_rejectedByHorizontal) {
      final delta = event.position - _startPosition;
      final dx = delta.dx.abs();
      final dy = delta.dy.abs();

      // If horizontal movement exceeds vertical movement by a clear margin,
      // this is an intentional horizontal swipe. Reject from vertical arena.
      if (dx > dy && dx > 8.0) {
        _rejectedByHorizontal = true;
        resolve(GestureDisposition.rejected);
        return;
      }
    }
    super.handleEvent(event);
  }
}
