/*
 * File: video_gesture_overlay.dart
 * Description: Gesture detector overlay handling horizontal scrubbing, vertical brightness (left) and volume (right) gestures with floating HUDs.
 */

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../../../core/services/device_hardware_service.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../viewmodel/video_player_view_model.dart';

/// Interactive gesture overlay detecting horizontal timeline scrub, left-side brightness, and right-side volume gestures.
class VideoGestureOverlay extends StatefulWidget {
  final VideoPlayerViewModel viewModel;
  final VoidCallback onTap;
  final Widget child;

  const VideoGestureOverlay({
    super.key,
    required this.viewModel,
    required this.onTap,
    required this.child,
  });

  @override
  State<VideoGestureOverlay> createState() => VideoGestureOverlayState();
}

/// Exposed state allowing parent to display custom HUD banners (e.g. aspect ratio change).
class VideoGestureOverlayState extends State<VideoGestureOverlay> {
  double _brightness = 0.5;
  bool _showBrightnessHud = false;
  Timer? _brightnessTimer;

  bool _showVolumeHud = false;
  Timer? _volumeTimer;

  String? _toastMessage;
  IconData? _toastIcon;
  Timer? _toastTimer;

  /// Returns current software brightness factor.
  double get brightness => _brightness;

  @override
  void initState() {
    super.initState();
    _brightness = DeviceHardwareService.instance.currentBrightness;
  }

  @override
  void dispose() {
    _brightnessTimer?.cancel();
    _volumeTimer?.cancel();
    _toastTimer?.cancel();
    super.dispose();
  }

  /// Displays a brief glassmorphic feedback HUD in the viewport center.
  void showCenterToast({required String message, required IconData icon}) {
    _toastTimer?.cancel();
    setState(() {
      _toastMessage = message;
      _toastIcon = icon;
    });
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double screenWidth) {
    final isLeft = details.globalPosition.dx < (screenWidth / 2);
    final delta = details.primaryDelta ?? 0.0;
    // Drag up is negative delta -> increases value
    final step = -delta / 250.0;

    if (isLeft) {
      // Brightness gesture (Left side swipe)
      _brightnessTimer?.cancel();
      final newBrightness = (_brightness + step).clamp(0.05, 1.0);
      setState(() {
        _brightness = newBrightness;
        _showBrightnessHud = true;
      });
      DeviceHardwareService.instance.setScreenBrightness(newBrightness);
      _brightnessTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showBrightnessHud = false);
      });
    } else {
      // Volume gesture (Right side swipe)
      _volumeTimer?.cancel();
      final currentVol = DeviceHardwareService.instance.currentVolume;
      final newVol = (currentVol + step).clamp(0.0, 1.0);
      DeviceHardwareService.instance.setVolume(newVol);
      widget.viewModel.setVolume(newVol);
      setState(() => _showVolumeHud = true);
      _volumeTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showVolumeHud = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final currentVolume = DeviceHardwareService.instance.currentVolume;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video Viewport Child
        widget.child,

        // Fallback Software Brightness Dimmer Overlay (when hardware brightness unavailable)
        if (!DeviceHardwareService.instance.isHardwareBrightnessActive)
          IgnorePointer(
            child: Container(
              color: Colors.black.withValues(
                alpha: (1.0 - _brightness).clamp(0.0, 0.85),
              ),
            ),
          ),

        // Gesture Detection Surface
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onDoubleTapDown: (details) {
            if (details.localPosition.dx < screenWidth / 2) {
              widget.viewModel.skipBackward();
            } else {
              widget.viewModel.skipForward();
            }
          },
          onHorizontalDragStart: (_) => widget.viewModel.onDragStart(),
          onHorizontalDragUpdate: (details) {
            widget.viewModel.onDragUpdate(details.primaryDelta ?? 0.0, screenWidth);
          },
          onHorizontalDragEnd: (_) => widget.viewModel.onDragEnd(),
          onHorizontalDragCancel: () => widget.viewModel.onDragEnd(),
          onVerticalDragUpdate: (details) => _onVerticalDragUpdate(details, screenWidth),
        ),

        // Volume HUD (Swipe on Right -> Displays on Opposite LEFT Side)
        if (_showVolumeHud)
          Positioned(
            left: 36,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildHudFloating(
                colors: colors,
                icon: currentVolume == 0
                    ? Icons.volume_mute_rounded
                    : currentVolume < 0.5
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
                percent: (currentVolume * 100).round(),
              ),
            ),
          ),

        // Brightness HUD (Swipe on Left -> Displays on Opposite RIGHT Side)
        if (_showBrightnessHud)
          Positioned(
            right: 36,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildHudFloating(
                colors: colors,
                icon: _brightness > 0.6
                    ? Icons.brightness_high_rounded
                    : _brightness > 0.25
                        ? Icons.brightness_medium_rounded
                        : Icons.brightness_low_rounded,
                percent: (_brightness * 100).round(),
              ),
            ),
          ),

        // Center Toast HUD (e.g. for Aspect Ratio or quick events)
        if (_toastMessage != null)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: colors.bgSurface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.60)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_toastIcon != null) ...[
                    Icon(_toastIcon, color: colors.accentPrimary, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _toastMessage!,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHudFloating({
    required AppColorsExtension colors,
    required IconData icon,
    required int percent,
  }) {
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: colors.accentPrimary,
            size: 26,
            shadows: const [
              Shadow(blurRadius: 10, color: Colors.black),
            ],
          ),
          const SizedBox(height: 12),
          // Vertical Indicator Track (Floating borderless)
          Container(
            width: 4,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 4,
                ),
              ],
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: 4,
                height: 100 * (percent / 100.0).clamp(0.0, 1.0),
                decoration: BoxDecoration(
                  color: colors.accentPrimary,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: colors.accentPrimary.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$percent%',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
              shadows: const [
                Shadow(blurRadius: 8, color: Colors.black),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
