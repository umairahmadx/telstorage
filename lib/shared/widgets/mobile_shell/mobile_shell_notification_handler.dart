/*
 * File: mobile_shell_notification_handler.dart
 * Description: Handles transfer notification actions and routes notification taps from the mobile shell.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/navigation/navigation_intent.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/services/transfer_queue_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/file_opener_helper.dart';

/// Resolves transfer notification actions without expanding the shell widget.
class MobileShellNotificationHandler {
  MobileShellNotificationHandler._();

  /// Handles a notification action or payload using the shell's current context.
  static void handle(BuildContext context, NotificationResponse details) {
    final payload = details.payload;
    final actionId = details.actionId;

    AppLogger.i('Notification response: actionId=$actionId, payload=$payload',
        tag: 'MobileShell');

    if (actionId != null && actionId.isNotEmpty) {
      if (actionId.startsWith('pause_')) {
        TransferQueueService.instance.pauseTask(actionId.replaceFirst('pause_', ''));
        return;
      } else if (actionId.startsWith('resume_')) {
        TransferQueueService.instance.resumeTask(actionId.replaceFirst('resume_', ''));
        return;
      } else if (actionId.startsWith('cancel_')) {
        TransferQueueService.instance.cancelTask(actionId.replaceFirst('cancel_', ''));
        return;
      } else if (actionId.startsWith('open_path:')) {
        FileOpenerHelper.openFile(
          context,
          filePath: actionId.replaceFirst('open_path:', ''),
        );
        return;
      } else if (actionId.startsWith('open_')) {
        final id = actionId.replaceFirst('open_', '');
        final job = ServiceLocator.instance.downloadQueue.allJobs
            .where((job) => job.fileId == id)
            .firstOrNull;
        final path = job?.localPath ??
            ServiceLocator.instance.downloadQueue.getCompletedPath(id);
        if (path != null) {
          FileOpenerHelper.openFile(
            context,
            filePath: path,
            mimeType: job?.mimeType,
            fileName: job?.name,
          );
        } else {
          ServiceLocator.instance.navigation
              .navigateTo(AppDestination.transferDownloads);
        }
        return;
      } else if (actionId.startsWith('copy_url:')) {
        _copyAndFeedback(context, actionId.replaceFirst('copy_url:', ''));
        return;
      } else if (actionId.startsWith('copy_')) {
        final id = actionId.replaceFirst('copy_', '');
        final share = ServiceLocator.instance.webShareQueue.allShares
            .where((share) => share.fileId == id)
            .firstOrNull;
        if (share?.shareUrl != null) {
          _copyAndFeedback(context, share!.shareUrl!);
        }
        return;
      } else if (actionId == 'view_all') {
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferActive);
        return;
      } else if (actionId == 'view_uploads') {
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferUploads);
        return;
      } else if (actionId == 'view_downloads') {
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferDownloads);
        return;
      } else if (actionId == 'view_shared') {
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferShared);
        return;
      }
    }

    if (payload == 'transfer_active') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferActive);
    } else if (payload == 'transfer_upload') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferUploads);
    } else if (payload == 'transfer_download') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferDownloads);
    } else if (payload == 'transfer_share') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferShared);
    }
  }

  static void _copyAndFeedback(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    HapticFeedback.lightImpact();
    if (!context.mounted) return;

    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: colors.success, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Share link copied: $url',
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
