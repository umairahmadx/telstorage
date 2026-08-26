/*
 * File: battery_optimization_helper.dart
 * Description: Helper providing battery optimization status checks and user prompts for uninterrupted background execution on aggressive OEM devices (Xiaomi, Huawei, Samsung, Oppo).
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../shared/widgets/dialogs/app_dialogs.dart';
import 'app_logger.dart';

/// Utility class for checking and requesting exemption from OEM battery killers.
class BatteryOptimizationHelper {
  BatteryOptimizationHelper._();

  /// Checks if battery optimization is already disabled for the app.
  static Future<bool> isOptimizationDisabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (e) {
      AppLogger.w('Failed to check battery optimization status: $e',
          tag: 'BatteryOptimization');
      return true;
    }
  }

  /// Requests exemption from Android battery optimizations.
  static Future<bool> requestOptimizationDisabled() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      return status.isGranted;
    } catch (e) {
      AppLogger.w('Failed to request battery optimization exemption: $e',
          tag: 'BatteryOptimization');
      return false;
    }
  }

  static bool _hasPromptedThisSession = false;

  /// Prompts user with a dialog if battery optimizations are active on Android.
  static Future<bool> maybePromptBatteryOptimization(
      BuildContext context) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _hasPromptedThisSession) {
      return true;
    }

    final isOptimized = !(await isOptimizationDisabled());
    if (!isOptimized) return true;

    _hasPromptedThisSession = true;

    if (!context.mounted) return false;

    final shouldRequest = await AppDialogs.showConfirm(
      context,
      title: 'Unrestricted Background Uploads',
      message:
          'To ensure large uploads complete uninterrupted when the screen is locked or app is closed, allow TelStorage to run without battery restrictions.',
      confirmText: 'Allow',
      cancelText: 'Not Now',
    );

    if (shouldRequest == true) {
      return await requestOptimizationDisabled();
    }
    return false;
  }
}
