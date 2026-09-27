/*
 * File: video_aspect_ratio_mode.dart
 * Description: Video player aspect ratio scaling modes (Best Fit, Fill Screen, 16:9, 4:3, Original).
 */

import 'package:flutter/widgets.dart';

/// Supported display aspect ratio presets for video playback.
enum VideoAspectRatioMode {
  /// Best Fit: scales video to fit within viewport maintaining original aspect ratio without cropping.
  fit('Best Fit', BoxFit.contain, null),

  /// Fill Screen: scales video to cover entire viewport, cropping edges if needed.
  fill('Fill Screen', BoxFit.cover, null),

  /// Fixed 16:9: forces widescreen 16:9 display frame.
  ratio16_9('16:9', BoxFit.contain, 16 / 9),

  /// Fixed 4:3: forces standard 4:3 display frame.
  ratio4_3('4:3', BoxFit.contain, 4 / 3);

  /// Human-readable label for sheet and UI.
  final String label;

  /// Underlying BoxFit applied to the video frame.
  final BoxFit boxFit;

  /// Optional forced aspect ratio override.
  final double? forcedAspectRatio;

  const VideoAspectRatioMode(this.label, this.boxFit, this.forcedAspectRatio);
}
