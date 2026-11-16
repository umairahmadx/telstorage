/*
 * File: backup_permission_helper.dart
 * Description: Permission prompts for enabling backup sources — media access
 * for albums, all-files access for directories, plus battery exemption.
 */

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/backup_rule.dart';
import '../services/device_media_scanner.dart';
import 'battery_optimization_helper.dart';
import 'storage_permission_helper.dart';

/// Requests the permissions a backup rule needs, then offers the
/// battery-optimization exemption so background runs are not killed.
abstract final class BackupPermissionHelper {
  /// Prompts for the source permission and battery exemption.
  ///
  /// Returns whether the source permission is granted. Prompt failures
  /// (e.g. unsupported host) fail open here — the run itself still gates
  /// on permission before scanning or uploading.
  static Future<bool> promptForRule(
    BuildContext context,
    BackupRule rule,
  ) async {
    var granted = true;
    try {
      if (rule.isDirectory) {
        granted = await StoragePermissionHelper.ensureStoragePermission(context);
      } else {
        granted = await DeviceMediaScanner.requestPermission();
      }
    } catch (_) {
      granted = true;
    }
    if (context.mounted) {
      await BatteryOptimizationHelper.maybePromptBatteryOptimization(context);
    }
    try {
      // Android 13+ gates the backup completion/progress notifications.
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}
    return granted;
  }
}