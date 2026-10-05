/*
 * File: device_hardware_service.dart
 * Description: Hardware abstraction service for controlling device brightness and media stream volume.
 */

import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:logger/logger.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:battery_plus/battery_plus.dart';

/// Centralized service handling native hardware brightness and system media volume.
class DeviceHardwareService {
  DeviceHardwareService._();

  /// Singleton access instance.
  static final DeviceHardwareService instance = DeviceHardwareService._();

  final Logger _logger = Logger(
    printer: PrettyPrinter(methodCount: 0, errorMethodCount: 3, lineLength: 80),
  );

  double _currentBrightness = 0.5;
  double _currentVolume = 1.0;
  bool _initialized = false;
  bool _hasHardwareBrightness = false;

  /// Returns whether hardware screen brightness control is actively available.
  bool get isHardwareBrightnessActive => _hasHardwareBrightness;

  /// Returns the current tracked brightness level (0.0 to 1.0).
  double get currentBrightness => _currentBrightness;

  /// Returns the current tracked volume level (0.0 to 1.0).
  double get currentVolume => _currentVolume;

  /// Initializes hardware state by querying current system brightness and volume.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final brightness = await ScreenBrightness().application;
      _currentBrightness = brightness.clamp(0.0, 1.0);
      _hasHardwareBrightness = true;
    } catch (e) {
      _logger.d('Could not read hardware screen brightness, using default fallback: $e');
    }

    try {
      await FlutterVolumeController.updateShowSystemUI(false);
      final vol = await FlutterVolumeController.getVolume(
        stream: AudioStream.music,
      );
      if (vol != null) {
        _currentVolume = vol.clamp(0.0, 1.0);
      }
    } catch (e) {
      _logger.d('Could not read hardware volume, using default fallback: $e');
    }
  }

  /// Sets hardware screen brightness (0.0 to 1.0).
  Future<void> setScreenBrightness(double brightness) async {
    _currentBrightness = brightness.clamp(0.0, 1.0);
    try {
      await ScreenBrightness().setApplicationScreenBrightness(_currentBrightness);
      _hasHardwareBrightness = true;
    } catch (e) {
      _logger.d('Hardware screen brightness error (falling back to software): $e');
    }
  }

  /// Restores system volume UI visibility and screen brightness when exiting the player.
  Future<void> restoreDefaults() async {
    try {
      await ScreenBrightness().resetApplicationScreenBrightness();
    } catch (e) {
      _logger.d('Hardware screen brightness reset error: $e');
    }
    try {
      await FlutterVolumeController.updateShowSystemUI(true);
    } catch (e) {
      _logger.d('Error restoring system volume UI: $e');
    }
  }

  /// Sets system media volume (0.0 to 1.0) while keeping native OS volume popup hidden.
  Future<void> setVolume(double volume) async {
    _currentVolume = volume.clamp(0.0, 1.0);
    try {
      await FlutterVolumeController.setVolume(
        _currentVolume,
        stream: AudioStream.music,
      );
    } catch (e) {
      _logger.d('Hardware system volume set error: $e');
    }
  }

  /// Checks if the device is currently charging.
  /// Uses battery_plus for accurate detection; returns true if unknown (optimistic).
  Future<bool> isCharging() async {
    try {
      final battery = Battery();
      final state = await battery.batteryState;
      return state == BatteryState.charging || state == BatteryState.full;
    } catch (e) {
      _logger.d('Battery state check failed, assuming charging: $e');
      return true; // Optimistic default for backup eligibility
    }
  }
}
