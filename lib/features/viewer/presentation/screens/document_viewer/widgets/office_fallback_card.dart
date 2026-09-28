/*
 * File: office_fallback_card.dart
 * Description: Full-screen fallback card for Office documents providing open-with-device-app launcher and file metadata.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:telstorage/core/models/file_record.dart';
import 'package:telstorage/core/theme/app_colors.dart';
import 'package:telstorage/core/theme/app_colors_extension.dart';
import 'package:telstorage/core/utils/app_logger.dart';
import 'package:telstorage/features/browser/presentation/screens/browser/widgets/browser_dialogs.dart';

/// Fullscreen preview card for Office documents.
class OfficeFallbackCard extends StatelessWidget {
  /// File metadata record.
  final FileRecord file;

  /// Local cached file if downloaded.
  final File? localFile;

  /// Constructs OfficeFallbackCard.
  const OfficeFallbackCard({
    super.key,
    required this.file,
    this.localFile,
  });

  Future<void> _handleOpenWithDeviceApp(BuildContext context) async {
    final path = localFile?.path;
    if (path == null || !File(path).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is still downloading…')),
      );
      return;
    }

    try {
      final result = await OpenFile.open(path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: ${result.message}')),
        );
      }
    } catch (e) {
      AppLogger.e('Failed to open Office file: $e',
          tag: 'OfficeFallbackCard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.filePptx.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 48,
                color: AppColors.filePptx,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              file.name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors?.textPrimary ?? AppColors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${file.formattedSize} • Office Document',
              style: TextStyle(
                fontSize: 13,
                color: colors?.textSecondary ?? AppColors.grey600,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open with Device App'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _handleOpenWithDeviceApp(context),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => BrowserDialogs.showFileDetail(context, file),
              child: Text(
                'View Metadata',
                style: TextStyle(
                  color: colors?.textSecondary ?? AppColors.grey600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
