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
import '../utils/local_file_stub.dart'
    if (dart.library.io) '../utils/local_file_native.dart';
import '../utils/native_save_helper.dart';
import 'download_service_contract.dart';
import 'folder_traversal_service.dart';
import 'notification_service.dart';
import 'service_locator.dart';
import 'transfer_concurrency_coordinator.dart';
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

  /// Compresses a collection of [entries] into [destinationZip] with streaming disk I/O.
  static Future<void> createZipFromFiles({
    required File destinationZip,
    required List<ZipEntry> entries,
    void Function(double progress, String status)? onProgress,
  }) async {
    final parentDir = destinationZip.parent;
    if (!parentDir.existsSync()) {
      await parentDir.create(recursive: true);
    }

    final encoder = ZipFileEncoder();
    try {
      encoder.create(destinationZip.path);
      final total = entries.length;

      for (var i = 0; i < total; i++) {
        final entry = entries[i];
        if (entry.file.existsSync()) {
          await encoder.addFile(entry.file, entry.archivePath);
        }
        final progress = total > 0 ? (i + 1) / total : 1.0;
        onProgress?.call(progress, 'Compressing ${i + 1}/$total items…');
      }
    } finally {
      try {
        await encoder.close();
      } catch (_) {}
    }
  }

  /// Downloads and packages folder contents into a temporary `.zip` file for web sharing.
  static Future<File?> packageFolderToTempZip({
    required FolderRecord folder,
    required List<FolderFileItem> items,
    required DownloadServiceContract downloadService,
    required String transferId,
    void Function(double progress, String status)? onProgress,
  }) async {
    final cleanFolderName = FolderTraversalService.sanitizeSegment(folder.name);
    final zipName = '$cleanFolderName.zip';
    final tempDir = Directory.systemTemp.createTempSync('web_share_zip_');
    final stagedZipFile = File('${tempDir.path}/$zipName');

    try {
      final List<ZipEntry> zipEntries = [];
      final Set<String> usedArchivePaths = <String>{};
      final total = items.length;

      for (var i = 0; i < total; i++) {
        if (isTaskCancelled(transferId)) {
          throw Exception('Share cancelled by user');
        }

        final item = items[i];
        onProgress?.call(
          total > 0 ? (i / total) * 0.7 : 0.0,
          'Preparing ${i + 1}/$total: ${item.file.name}',
        );

        final bytes = await downloadService.downloadFile(
          item.file,
          (chunkProgress, _) {
            final fileBase = total > 0 ? (i / total) * 0.7 : 0.0;
            final fileSpan = total > 0 ? (1.0 / total) * 0.7 : 0.7;
            onProgress?.call(
              fileBase + (chunkProgress * fileSpan),
              'Downloading ${i + 1}/$total: ${item.file.name}',
            );
          },
        );

        final safeArchivePath =
            disambiguateArchivePath(item.relativePath, usedArchivePaths);
        final targetFile = File('${tempDir.path}/$safeArchivePath');
        await targetFile.parent.create(recursive: true);
        await targetFile.writeAsBytes(bytes);

        zipEntries.add(ZipEntry(file: targetFile, archivePath: safeArchivePath));
      }

      if (isTaskCancelled(transferId)) {
        throw Exception('Share cancelled by user');
      }

      onProgress?.call(0.75, 'Compressing folder into ZIP…');
      await createZipFromFiles(
        destinationZip: stagedZipFile,
        entries: zipEntries,
        onProgress: (compProgress, compStatus) {
          onProgress?.call(0.75 + (compProgress * 0.25), compStatus);
        },
      );

      return stagedZipFile;
    } catch (e) {
      if (tempDir.existsSync()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Downloads all files inside [folder] recursively and packages them into a `.zip` archive.
  static Future<String?> exportFolderAsZip({
    required FolderRecord folder,
    required List<FolderFileItem> items,
    required DownloadServiceContract downloadService,
  }) async {
    final taskId = 'zip_${folder.id}_${DateTime.now().millisecondsSinceEpoch}';
    final cleanFolderName = FolderTraversalService.sanitizeSegment(folder.name);
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

    // Step 1: Register in-memory active task synchronously
    TransferQueueService.instance.addTask(TransferTask(
      id: taskId,
      name: zipName,
      type: TransferType.download,
      sizeMb: stats.totalSizeMb,
      addedAt: DateTime.now(),
      status: TransferStatus.preparing,
      currentStage: 'Preparing archive…',
    ));

    // Step 2: Register initial download job in Hive with start-write guard
    try {
      if (ServiceLocator.instance.isInitialized) {
        await ServiceLocator.instance.downloadQueue.addOrUpdateZipJob(
          fileId: taskId,
          name: zipName,
          mimeType: 'application/zip',
          sizeMb: stats.totalSizeMb,
          status: 'downloading',
          progress: 0.0,
          addedAt: DateTime.now(),
          subpath: 'zip',
        );
      }
    } catch (e, st) {
      AppLogger.e('Failed to initialize ZIP download tracking in Hive: $e',
          error: e, stackTrace: st, tag: 'ZipArchive');
      TransferQueueService.instance.updateTask(
        taskId,
        status: TransferStatus.failed,
        error: 'Failed to initialize download tracking: $e',
        currentStage: 'Initialization failed',
      );
      return null;
    }

    return await TransferConcurrencyCoordinator.instance.runGuarded(() async {
      Directory? tempDir;
      String? savedZipPath;
      try {
        tempDir = await Directory.systemTemp
            .createTemp('telstorage_zip_${folder.id}_');
        final zipEntries = <ZipEntry>[];
        final usedArchivePaths = <String>{};
        final total = items.length;

        for (var i = 0; i < total; i++) {
          // EC-13: Cancellation check before downloading each file
          if (isTaskCancelled(taskId)) {
            AppLogger.i('ZIP export cancelled for "${folder.name}"',
                tag: 'ZipArchive');
            // Best-effort Hive write; always surface cancellation state to TQS even if Hive write itself fails
            try {
              if (ServiceLocator.instance.isInitialized) {
                await ServiceLocator.instance.downloadQueue.addOrUpdateZipJob(
                  fileId: taskId,
                  name: zipName,
                  mimeType: 'application/zip',
                  sizeMb: stats.totalSizeMb,
                  status: 'cancelled',
                );
              }
            } catch (_) {}
            TransferQueueService.instance.updateTask(
              taskId,
              status: TransferStatus.cancelled,
              currentStage: 'Cancelled',
            );
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
              TransferQueueService.instance
                  .updateTask(taskId, progress: overall);
            },
          );

          // EC-14: Disambiguate duplicate archive paths
          final safeArchivePath =
              disambiguateArchivePath(item.relativePath, usedArchivePaths);
          final targetFile = File('${tempDir.path}/$safeArchivePath');
          await targetFile.parent.create(recursive: true);
          await targetFile.writeAsBytes(bytes);

          zipEntries
              .add(ZipEntry(file: targetFile, archivePath: safeArchivePath));
        }

        if (isTaskCancelled(taskId)) {
          try {
            if (ServiceLocator.instance.isInitialized) {
              await ServiceLocator.instance.downloadQueue.addOrUpdateZipJob(
                fileId: taskId,
                name: zipName,
                mimeType: 'application/zip',
                sizeMb: stats.totalSizeMb,
                status: 'cancelled',
              );
            }
          } catch (_) {}
          TransferQueueService.instance.updateTask(
            taskId,
            status: TransferStatus.cancelled,
            currentStage: 'Cancelled',
          );
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
          try {
            if (ServiceLocator.instance.isInitialized) {
              await ServiceLocator.instance.downloadQueue.addOrUpdateZipJob(
                fileId: taskId,
                name: zipName,
                mimeType: 'application/zip',
                sizeMb: stats.totalSizeMb,
                status: 'cancelled',
              );
            }
          } catch (_) {}
          TransferQueueService.instance.updateTask(
            taskId,
            status: TransferStatus.cancelled,
            currentStage: 'Cancelled',
          );
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
          savedZipPath = saveResult.savedPath;

          // Step 1: Await Hive persistence first
          try {
            if (ServiceLocator.instance.isInitialized) {
              await ServiceLocator.instance.downloadQueue.addOrUpdateZipJob(
                fileId: taskId,
                name: zipName,
                mimeType: 'application/zip',
                sizeMb: stats.totalSizeMb,
                status: 'completed',
                localPath: saveResult.savedPath,
                completedAt: DateTime.now(),
                progress: 1.0,
              );
            }
          } catch (e, st) {
            AppLogger.e('Failed to persist completed ZIP job to Hive: $e',
                error: e, stackTrace: st, tag: 'ZipArchive');
            TransferQueueService.instance.updateTask(
              taskId,
              status: TransferStatus.failed,
              error: 'Failed to save download record: $e',
              currentStage: 'Failed to record download',
            );
            return null;
          }

          // Step 2: ONLY executed when Step 1 succeeded
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
          try {
            if (ServiceLocator.instance.isInitialized) {
              await ServiceLocator.instance.downloadQueue.addOrUpdateZipJob(
                fileId: taskId,
                name: zipName,
                mimeType: 'application/zip',
                sizeMb: stats.totalSizeMb,
                status: 'cancelled',
              );
            }
          } catch (_) {}
          TransferQueueService.instance.updateTask(
            taskId,
            status: TransferStatus.cancelled,
            currentStage: 'Cancelled',
          );
          return null;
        }

        // Clean up partial saved file on error if partially created
        if (savedZipPath != null) {
          try {
            await deleteLocalFileIfExists(savedZipPath);
          } catch (_) {}
        }

        AppLogger.e('ZIP export failed for "${folder.name}": $e',
            error: e, stackTrace: st, tag: 'ZipArchive');

        // Best-effort Hive write; always surface failure state to TQS even if Hive write itself fails
        try {
          if (ServiceLocator.instance.isInitialized) {
            await ServiceLocator.instance.downloadQueue.addOrUpdateZipJob(
              fileId: taskId,
              name: zipName,
              mimeType: 'application/zip',
              sizeMb: stats.totalSizeMb,
              status: 'failed',
              error: e.toString(),
            );
          }
        } catch (_) {}

        TransferQueueService.instance.updateTask(
          taskId,
          status: TransferStatus.failed,
          error: e.toString(),
          currentStage: 'Export failed: $e',
        );
        await NotificationService.instance.showCompletionNotification(
          title: 'ZIP Export Failed',
          body: 'Failed to export ${folder.name}.zip',
          bigText: 'Failed to export ${folder.name}.zip\n\nError: $e',
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
    });
  }
}
