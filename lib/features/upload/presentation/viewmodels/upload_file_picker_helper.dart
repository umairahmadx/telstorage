/*
 * File: upload_file_picker_helper.dart
 * Description: Unified helper providing in-app device storage picking, directory uploads, and concurrency locking.
 */

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/navigation/navigation_intent.dart';
import '../../../../core/services/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/battery_optimization_helper.dart';
import '../../../../core/utils/storage_permission_helper.dart';
import '../../../../shared/widgets/device_file_picker/device_file_picker_sheet.dart';
import '../../../../shared/widgets/device_file_picker/device_media_picker_sheet.dart';
import '../../../../shared/widgets/device_file_picker/device_media_scanner.dart';
import 'upload_folder_helper.dart';
import 'upload_view_model.dart';

/// Static helper managing zero-copy in-app file picking, folder scanning, and concurrency mutex locking.
abstract final class UploadFilePickerHelper {
  static bool _isPicking = false;

  /// Whether a file or folder picking operation is currently active.
  static bool get isPicking => _isPicking;

  /// Opens the in-app device file picker sheet for direct, zero-copy uploads of any size.
  static Future<void> pickAndUploadFiles({
    required BuildContext context,
    required String? folderId,
    required UploadBloc uploadBloc,
  }) async {
    if (_isPicking) return;
    _isPicking = true;

    try {
      final selectedFiles = await DeviceFilePickerSheet.show(context);
      if (!context.mounted || selectedFiles == null || selectedFiles.isEmpty) return;

      final List<UploadTask> tasks = [];
      const uuid = Uuid();

      for (final file in selectedFiles) {
        if (!file.existsSync()) continue;
        final name = file.uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty,
          orElse: () => 'file',
        );
        final size = file.lengthSync();

        tasks.add(UploadTask(
          id: uuid.v4(),
          path: file.path,
          name: name,
          size: size,
          folderId: folderId,
          isTemporaryCacheFile: false, // Strict: Never delete permanent device files
        ));
      }

      if (tasks.isNotEmpty && context.mounted) {
        await BatteryOptimizationHelper.maybePromptBatteryOptimization(context);
        if (!context.mounted) return;
        uploadBloc.add(AddUploads(tasks));
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferUploads);
      }
    } catch (e) {
      AppLogger.e('Failed to pick files from device: $e', tag: 'UploadFilePicker');
      if (context.mounted) {
        final colors = Theme.of(context).extension<AppColorsExtension>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting files: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: colors?.error,
          ),
        );
      }
    } finally {
      _isPicking = false;
    }
  }

  /// Opens the device media picker for zero-copy photo/video selection and upload.
  static Future<void> pickAndUploadMedia({
    required BuildContext context,
    required String? folderId,
    required UploadBloc uploadBloc,
  }) async {
    if (_isPicking) return;
    _isPicking = true;

    try {
      if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
        // Web/Desktop fallback: use FilePicker with media filter
        final result = await FilePicker.platform.pickFiles(
          type: FileType.media,
          allowMultiple: true,
        );
        if (result == null || !context.mounted) return;
        final tasks = result.files
            .where((f) => f.path != null || f.bytes != null)
            .map((f) => UploadTask(
                  id: const Uuid().v4(),
                  path: f.path,
                  bytes: f.bytes,
                  name: f.name,
                  size: f.size,
                  folderId: folderId,
                ))
            .toList();
        if (tasks.isNotEmpty && context.mounted) {
          uploadBloc.add(AddUploads(tasks));
          ServiceLocator.instance.navigation
              .navigateTo(AppDestination.transferUploads);
        }
        return;
      }

      // Mobile: open our custom media picker
      final selectedAssets = await DeviceMediaPickerSheet.show(context);
      if (selectedAssets == null || selectedAssets.isEmpty || !context.mounted) {
        return;
      }

      final List<UploadTask> tasks = [];
      const uuid = Uuid();

      for (final asset in selectedAssets) {
        final (path, isTemporary) =
            await DeviceMediaScanner.resolveUploadPath(asset);
        final file = File(path);
        if (!file.existsSync()) continue;

        tasks.add(UploadTask(
          id: uuid.v4(),
          path: path,
          name: asset.title ?? 'media_${asset.id}',
          size: await file.length(),
          folderId: folderId,
          isTemporaryCacheFile: isTemporary,
        ));
      }

      if (tasks.isNotEmpty && context.mounted) {
        await BatteryOptimizationHelper.maybePromptBatteryOptimization(context);
        if (!context.mounted) return;
        uploadBloc.add(AddUploads(tasks));
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferUploads);
      }
    } catch (e) {
      AppLogger.e('Failed to pick media: $e', tag: 'UploadFilePicker');
      if (context.mounted) {
        final colors = Theme.of(context).extension<AppColorsExtension>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error selecting media: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: colors?.error,
          ),
        );
      }
    } finally {
      _isPicking = false;
    }
  }

  /// Opens directory picker with concurrency protection and enqueues folder hierarchy for upload.
  static Future<void> pickAndUploadFolder({
    required BuildContext context,
    required String? targetParentFolderId,
    required UploadBloc uploadBloc,
  }) async {
    if (_isPicking) return;
    _isPicking = true;

    try {
      final hasPermission =
          await StoragePermissionHelper.ensureStoragePermission(context);
      if (!hasPermission || !context.mounted) return;

      final dirPath = await FilePicker.platform.getDirectoryPath();
      if (dirPath == null || dirPath.isEmpty || !context.mounted) return;

      final scanResult = await UploadFolderHelper.scanAndQueueFolder(
        dirPath: dirPath,
        targetParentFolderId: targetParentFolderId,
        storageRepository: ServiceLocator.instance.storageRepository,
        uploadBloc: uploadBloc,
      );

      if (scanResult.filesCount > 0 && context.mounted) {
        await BatteryOptimizationHelper.maybePromptBatteryOptimization(context);
        if (!context.mounted) return;
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferUploads);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The selected folder contains no files to upload.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FolderInaccessibleException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
            backgroundColor:
                Theme.of(context).extension<AppColorsExtension>()?.error,
          ),
        );
      }
    } catch (e) {
      AppLogger.e('Failed to pick folder: $e', tag: 'UploadFilePicker');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to read folder: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor:
                Theme.of(context).extension<AppColorsExtension>()?.error,
          ),
        );
      }
    } finally {
      _isPicking = false;
    }
  }
}
