/*
 * File: responsive_page_scroll_physics.dart
 * Description: High-responsiveness PageView scroll physics with relaxed drag-commit threshold and bouncy overscroll.
 */

import 'package:flutter/material.dart';

/// Custom [PageScrollPhysics] that lowers the drag distance threshold required
/// to commit a page turn from Flutter's default 50% down to a natural 15-20%,
/// preventing "too tight" swipe requirements and dropped-velocity snap-backs.
class ResponsivePageScrollPhysics extends PageScrollPhysics {
  /// Fraction of page width required to commit a page turn on finger release
  /// when velocity is low or interrupted by background loading.
  final double dragThresholdRatio;

  /// Minimum fling velocity in logical pixels/sec to commit a page turn.
  final double flingVelocityThreshold;

  /// Callback returning the page index where the current gesture started.
  final ValueGetter<double?>? getDragStartPage;

  /// Constructs a [ResponsivePageScrollPhysics].
  const ResponsivePageScrollPhysics({
    super.parent,
    this.dragThresholdRatio = 0.18,
    this.flingVelocityThreshold = 120.0,
    this.getDragStartPage,
  });

  @override
  ResponsivePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ResponsivePageScrollPhysics(
      parent: buildParent(ancestor),
      dragThresholdRatio: dragThresholdRatio,
      flingVelocityThreshold: flingVelocityThreshold,
      getDragStartPage: getDragStartPage,
    );
  }

  double _getPage(ScrollMetrics position) {
    return position.pixels / position.viewportDimension;
  }

  double _getPixels(ScrollMetrics position, double page) {
    return page * position.viewportDimension;
  }

  double _getTargetPixels(
      ScrollMetrics position, Tolerance tolerance, double velocity) {
    final double page = _getPage(position);
    final double? startPage = getDragStartPage?.call();

    // If starting page is known, resolve direction-aware target
    if (startPage != null) {
      final double deltaFromStart = page - startPage;

      if (velocity < -flingVelocityThreshold) {
        // Flicked towards previous page
        return _getPixels(position, (startPage - 1.0).roundToDouble());
      } else if (velocity > flingVelocityThreshold) {
        // Flicked towards next page
        return _getPixels(position, (startPage + 1.0).roundToDouble());
      } else if (deltaFromStart > dragThresholdRatio) {
        // Dragged past threshold towards next page
        return _getPixels(position, (startPage + 1.0).roundToDouble());
      } else if (deltaFromStart < -dragThresholdRatio) {
        // Dragged past threshold towards previous page
        return _getPixels(position, (startPage - 1.0).roundToDouble());
      } else {
        // Released without reaching threshold -> snap back to start page
        return _getPixels(position, startPage.roundToDouble());
      }
    }

    // Fallback if startPage is unavailable
    double targetPage = page;
    if (velocity < -flingVelocityThreshold) {
      targetPage -= 0.5;
    } else if (velocity > flingVelocityThreshold) {
      targetPage += 0.5;
    }
    return _getPixels(position, targetPage.roundToDouble());
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // If out of range at the boundaries, defer to parent (e.g. BouncingScrollPhysics)
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final Tolerance tolerance = toleranceFor(position);
    final double target = _getTargetPixels(position, tolerance, velocity);
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}
