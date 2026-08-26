/*
 * File: zip_archive_service.dart
 * Description: Service for creating compressed ZIP archives from folder file structures with live transfer queue tracking, cancellation support, and cleanup.
 */

import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import '../models/folder_record.dart';
import '../models/transfer_task.dart';
import '../utils/app_logger.dart';
import '../utils/native_save_helper.dart';
import 'download_service_contract.dart';
import 'folder_traversal_service.dart';
import 'notification_service.dart';
import 'transfer_queue_service.dart';

/// Entry representing a physical file and its path in the zip archive.
class ZipEntry {
  final File file;
  final String archivePath;

  const ZipEntry({required this.file, required this.archivePath});
}

/// Service that archives folder hierarchies into `.zip` files.
abstract final class ZipArchiveService {
  /// Resolves non-colliding archive paths when duplicate filenames exist.
  static String disambiguateArchivePath(
      String relativePath, Set<String> usedPaths) {
    if (usedPaths.add(relativePath)) {
      return relativePath;
    }
    final dir = p.posix.dirname(relativePath);
    final ext = p.posix.extension(relativePath);
    final nameWithoutExt = p.posix.basenameWithoutExtension(relativePath);

    var counter = 1;
    while (true) {
      final candidate = dir == '.'
          ? '$nameWithoutExt ($counter)$ext'
          : '$dir/$nameWithoutExt ($counter)$ext';
      if (usedPaths.add(candidate)) {
        return candidate;
      }
      counter++;
    }
  }

  /// Checks whether a background transfer task has been cancelled.
  static bool isTaskCancelled(String taskId) {
    final match =
        TransferQueueService.instance.tasks.where((t) => t.id == taskId);
    return match.isEmpty || match.first.status == TransferStatus.cancelled;
  }

  /// Compresses a collection of [entries] into [destinationZip].
  static Future<void> createZipFromFiles({
    required File destinationZip,
    required List<ZipEntry> entries,
    void Function(double progress, String status)? onProgress,
  }) async {
    final parentDir = destinationZip.parent;
    if (!parentDir.existsSync()) {
      await parentDir.create(recursive: true);
    }

    final archive = Archive();
    final total = entries.length;

    for (var i = 0; i < total; i++) {
      final entry = entries[i];
      if (entry.file.existsSync()) {
        final bytes = await entry.file.readAsBytes();
        archive.addFile(ArchiveFile(
          entry.archivePath,
          bytes.length,
          bytes,
        ));
      }
      final progress = total > 0 ? (i + 1) / total : 1.0;
      onProgress?.call(progress, 'Compressing ${i + 1}/$total items…');
    }

    final zipData = ZipEncoder().encode(archive);
    await destinationZip.writeAsBytes(zipData);
  }

  /// Downloads all files inside [folder] recursively and packages them into a `.zip` archive.
  static Future<String?> exportFolderAsZip({
    required FolderRecord folder,
    required List<FolderFileItem> items,
    required DownloadServiceContract downloadService,
  }) async {
    final taskId = 'zip_${folder.id}_${DateTime.now().millisecondsSinceEpoch}';
    final cleanFolderName =
        FolderTraversalService.sanitizeSegment(folder.name);
    final zipName = '$cleanFolderName.zip';
    final stats = FolderTraversalService.calculateStats(items);

    // EC-11: Guard against empty folder export
    if (items.isEmpty) {
      TransferQueueService.instance.addTask(TransferTask(
        id: taskId,
        name: zipName,
        type: TransferType.download,
        sizeMb: 0,
        addedAt: DateTime.now(),
        status: TransferStatus.failed,
        error: 'Folder contains no files to archive',
        currentStage: 'Folder is empty',
      ));
      return null;
    }

    TransferQueueService.instance.addTask(TransferTask(
      id: taskId,
      name: zipName,
      type: TransferType.download,
      sizeMb: stats.totalSizeMb,
      addedAt: DateTime.now(),
      status: TransferStatus.preparing,
      currentStage: 'Preparing archive…',
    ));

    Directory? tempDir;
    try {
      tempDir =
          await Directory.systemTemp.createTemp('telstorage_zip_${folder.id}_');
      final zipEntries = <ZipEntry>[];
      final usedArchivePaths = <String>{};
      final total = items.length;

      for (var i = 0; i < total; i++) {
        // EC-13: Cancellation check before downloading each file
        if (isTaskCancelled(taskId)) {
          AppLogger.i('ZIP export cancelled for "${folder.name}"',
              tag: 'ZipArchive');
          return null;
        }

        final item = items[i];
        final itemProgressBase = i / (total > 0 ? total : 1);
        final itemProgressStep = 1.0 / (total > 0 ? total : 1);

        TransferQueueService.instance.updateTask(
          taskId,
          progress: itemProgressBase * 0.8,
          currentStage: 'Downloading ${i + 1}/$total: ${item.file.name}',
        );

        final bytes = await downloadService.downloadFile(
          item.file,
          (chunkProgress, _) {
            final overall =
                (itemProgressBase + (chunkProgress * itemProgressStep)) * 0.8;
            TransferQueueService.instance.updateTask(taskId, progress: overall);
          },
        );

        // EC-14: Disambiguate duplicate archive paths
        final safeArchivePath =
            disambiguateArchivePath(item.relativePath, usedArchivePaths);
        final targetFile = File('${tempDir.path}/$safeArchivePath');
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(bytes);

        zipEntries.add(ZipEntry(file: targetFile, archivePath: safeArchivePath));
      }

      if (isTaskCancelled(taskId)) {
        return null;
      }

      TransferQueueService.instance.updateTask(
        taskId,
        progress: 0.85,
        currentStage: 'Compressing archive…',
      );

      final stagedZipFile = File('${tempDir.path}/$zipName');
      await createZipFromFiles(
        destinationZip: stagedZipFile,
        entries: zipEntries,
        onProgress: (p, status) {
          TransferQueueService.instance.updateTask(
            taskId,
            progress: 0.85 + (p * 0.1),
            currentStage: status,
          );
        },
      );

      if (isTaskCancelled(taskId)) {
        return null;
      }

      TransferQueueService.instance.updateTask(
        taskId,
        progress: 0.95,
        currentStage: 'Saving to Downloads…',
      );

      final zipBytes = await stagedZipFile.readAsBytes();
      final saveResult = await saveNative(
        zipBytes,
        zipName,
        subpath: 'zip',
      );

      if (saveResult.success) {
        TransferQueueService.instance.updateTask(
          taskId,
          status: TransferStatus.completed,
          progress: 1.0,
          currentStage: 'Export completed',
        );

        await NotificationService.instance.showCompletionNotification(
          title: 'Folder ZIP Exported',
          body: '$zipName has been created and saved to Downloads.',
          payload: 'transfer_download',
          actions: [
            if (saveResult.savedPath != null)
              AndroidNotificationAction(
                'open_path:${saveResult.savedPath}',
                'Open ZIP',
                showsUserInterface: true,
              ),
            const AndroidNotificationAction(
              'view_downloads',
              'View Downloads',
              showsUserInterface: true,
            ),
          ],
        );

        return saveResult.savedPath;
      } else {
        throw Exception(saveResult.message);
      }
    } catch (e, st) {
      if (isTaskCancelled(taskId)) {
        return null;
      }
      AppLogger.e('ZIP export failed for "${folder.name}": $e',
          error: e, stackTrace: st, tag: 'ZipArchive');
      TransferQueueService.instance.updateTask(
        taskId,
        status: TransferStatus.failed,
        error: e.toString(),
        currentStage: 'Export failed: $e',
      );
      await NotificationService.instance.showCompletionNotification(
        title: 'ZIP Export Failed',
        body: 'Failed to export ${folder.name}.zip: $e',
        payload: 'transfer_download',
      );
      return null;
    } finally {
      if (tempDir != null && tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
