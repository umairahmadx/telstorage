/*
 * File: storage_permission_helper.dart
 * Description: Helper providing storage permission checks and user prompts for directory scanning and file uploads across Android versions.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../shared/widgets/dialogs/app_dialogs.dart';
import 'app_logger.dart';

/// Utility class for verifying and requesting storage permissions required for directory scanning.
abstract final class StoragePermissionHelper {
  /// Checks if storage permissions are granted to scan and read folders.
  static Future<bool> hasStoragePermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    try {
      // Android 11+ (API 30+) requires manageExternalStorage for directory listing
      final manageStatus = await Permission.manageExternalStorage.status;
      if (manageStatus.isGranted) return true;

      // Android 10 and below fallback
      final storageStatus = await Permission.storage.status;
      return storageStatus.isGranted;
    } catch (e) {
      AppLogger.w('Failed to check storage permission status: $e',
          tag: 'StoragePermission');
      return true;
    }
  }

  /// Prompts user and requests appropriate storage permissions for folder upload.
  static Future<bool> ensureStoragePermission(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    final hasPermission = await hasStoragePermission();
    if (hasPermission) return true;

    if (!context.mounted) return false;

    // Show educational prompt explaining why permission is required
    final shouldProceed = await AppDialogs.showConfirm(
      context,
      title: 'Storage Permission Required',
      message:
          'To scan folders and upload files from your device, TelStorage needs permission to access files in the selected folder.',
      confirmText: 'Grant Permission',
      cancelText: 'Cancel',
    );

    if (shouldProceed != true) return false;

    try {
      // First attempt manageExternalStorage (Android 11+)
      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) return true;

      // Also request standard storage permission (Android 10 and below)
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      // If permanently denied or restricted, offer to open settings
      if (manageStatus.isPermanentlyDenied ||
          manageStatus.isRestricted ||
          storageStatus.isPermanentlyDenied) {
        if (!context.mounted) return false;
        final openSettings = await AppDialogs.showConfirm(
          context,
          title: 'Permission Denied',
          message:
              'Storage access is required to read folder contents. Please enable "All files access" or "Storage" in App Settings.',
          confirmText: 'Open Settings',
          cancelText: 'Cancel',
        );

        if (openSettings == true) {
          await openAppSettings();
        }
      }

      return await hasStoragePermission();
    } catch (e) {
      AppLogger.e('Error requesting storage permissions: $e',
          tag: 'StoragePermission');
      return false;
    }
  }
}
