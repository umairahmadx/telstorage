/*
 * File: storage_reconciler.dart
 * Description: Service for auditing and purging orphaned Telegram files, leftover chunks, and reconciling remote partitions.
 */

import 'dart:convert';
import 'package:hive/hive.dart';
import '../constants/app_constants.dart';
import '../models/app_metadata.dart';
import '../models/pending_action.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import 'hive_service.dart';
import 'metadata_service.dart';
import 'telegram_service.dart';

/// Summary report returned after completing storage reconciliation.
class ReconciliationReport {
  final int orphanedFilesCleaned;
  final int chunksDeleted;
  final double spaceFreedMb;
  final int partitionsCleaned;
  final List<String> cleanedFileNames;

  const ReconciliationReport({
    required this.orphanedFilesCleaned,
    required this.chunksDeleted,
    required this.spaceFreedMb,
    required this.partitionsCleaned,
    this.cleanedFileNames = const [],
  });

  bool get hasCleaned =>
      orphanedFilesCleaned > 0 || chunksDeleted > 0 || partitionsCleaned > 0;
}

/// Service auditing remote Telegram partitions against local Hive data and purging leftovers.
class StorageReconciler {
  final MetadataService _metadata;
  final TelegramService _telegram;
  final HiveService _hive;

  StorageReconciler(this._metadata, this._telegram, this._hive);

  /// Audits all remote partitions and bulk-purges orphaned files, chunk messages, and empty partitions.
  Future<ReconciliationReport> reconcileAndCleanRemoteStorage({
    Function(double progress, String status)? onProgress,
  }) async {
    if (!await Connectivity.hasConnection()) {
      throw OfflineException('Cannot reconcile storage: device is offline.');
    }

    int orphanedFilesCleaned = 0;
    int chunksDeleted = 0;
    double spaceFreedMb = 0.0;
    int partitionsCleaned = 0;
    final List<String> cleanedFileNames = [];
    final Set<int> messageIdsToPurge = {};

    try {
      onProgress?.call(0.05, 'Scanning remote storage index...');
      AppLogger.i('Beginning remote storage audit and reconciliation...',
          tag: 'StorageReconciler');

      final appMeta = await _metadata.fetch();
      final localFileIds = _hive.allFiles.map((f) => f.fileId).toSet();
      final localFolderIds = _hive.allFolders.map((f) => f.id).toSet();

      // Read protected files from pending actions
      final Set<String> protectedFileIds = {};
      final Set<String> protectedFolderIds = {};
      try {
        if (Hive.isBoxOpen(AppConstants.pendingActionsBox)) {
          final pendingBox =
              Hive.box<PendingAction>(AppConstants.pendingActionsBox);
          for (final action in pendingBox.values) {
            final p = action.payload;
            if (p['fileId'] != null) {
              protectedFileIds.add(p['fileId'].toString());
            }
            if (p['folderId'] != null) {
              protectedFolderIds.add(p['folderId'].toString());
            }
            if (p['newFileId'] != null) {
              protectedFileIds.add(p['newFileId'].toString());
            }
            if (p['fileMeta'] is Map && p['fileMeta']['file_id'] != null) {
              protectedFileIds.add(p['fileMeta']['file_id'].toString());
            }
          }
        }
      } catch (e) {
        AppLogger.w('Could not read pending actions: $e',
            tag: 'StorageReconciler', error: e);
      }

      final partitionIds = <String>{
        AppConstants.rootFolderPartitionId,
        ...appMeta.folderPartitionsMap.keys,
      };

      int scannedPartitions = 0;
      final totalPartitions = partitionIds.length;

      for (final pId in partitionIds) {
        scannedPartitions++;
        final progressFraction =
            0.1 + (0.5 * (scannedPartitions / totalPartitions));
        onProgress?.call(progressFraction,
            'Auditing partition $pId ($scannedPartitions/$totalPartitions)...');

        final partition = await _metadata.fetchFolderPartition(pId);
        if (partition == null) continue;

        final survivingFiles = <FileRef>[];
        bool partitionModified = false;

        final isOrphanFolder = pId != AppConstants.rootFolderPartitionId &&
            !localFolderIds.contains(pId) &&
            !protectedFolderIds.contains(pId);

        for (final ref in partition.files) {
          final isOrphanFile = isOrphanFolder ||
              (!localFileIds.contains(ref.fileId) &&
                  !protectedFileIds.contains(ref.fileId));

          if (isOrphanFile) {
            orphanedFilesCleaned++;
            spaceFreedMb += (ref.sizeMb ?? 0.0);
            cleanedFileNames.add(ref.name);
            partitionModified = true;

            if (ref.metadataMessageId != null && ref.metadataMessageId! > 0) {
              messageIdsToPurge.add(ref.metadataMessageId!);
            }

            // Attempt to retrieve chunks
            if (ref.metaFileId.isNotEmpty) {
              try {
                final bytes = await _telegram.downloadByFileId(ref.metaFileId);
                final metaJson =
                    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
                final chunks = metaJson['chunks'] as List? ?? [];
                for (final chunk in chunks) {
                  final cId = chunk['message_id'];
                  if (cId is int && cId > 0) {
                    messageIdsToPurge.add(cId);
                    chunksDeleted++;
                  }
                }
                final thumbMsgId = metaJson['thumbnail_message_id'];
                if (thumbMsgId is int && thumbMsgId > 0) {
                  messageIdsToPurge.add(thumbMsgId);
                }
              } catch (e) {
                AppLogger.w(
                  'Could not fetch chunk metadata for orphan ${ref.fileId}: $e',
                  tag: 'StorageReconciler',
                  error: e,
                );
              }
            }
          } else {
            survivingFiles.add(ref);
          }
        }

        if (partitionModified) {
          partitionsCleaned++;
          if (survivingFiles.isEmpty &&
              pId != AppConstants.rootFolderPartitionId) {
            if (partition.messageId > 0) {
              messageIdsToPurge.add(partition.messageId);
            }
            appMeta.folderPartitionsMap.remove(pId);
            await _hive.removeFolderPartitionMessageId(pId);
          } else {
            await _metadata.updatePartitionFiles(appMeta, pId, survivingFiles);
          }
        }
      }

      // Bulk purge messages from Telegram
      if (messageIdsToPurge.isNotEmpty) {
        onProgress?.call(0.75,
            'Purging ${messageIdsToPurge.length} leftover messages from Telegram...');
        AppLogger.i(
          'Executing bulk purge of ${messageIdsToPurge.length} Telegram messages',
          tag: 'StorageReconciler',
        );
        await _telegram.deleteMessages(messageIdsToPurge.toList());
      }

      // Compact and save updated AppMetadata
      onProgress?.call(0.9, 'Updating remote catalog...');
      appMeta.totalFiles =
          (appMeta.totalFiles - orphanedFilesCleaned).clamp(0, 10000000);
      appMeta.storageUsedMb =
          (appMeta.storageUsedMb - spaceFreedMb).clamp(0.0, 10000000.0);
      appMeta.recentFiles.removeWhere((f) =>
          !localFileIds.contains(f.fileId) &&
          !protectedFileIds.contains(f.fileId));
      appMeta.folders.removeWhere((f) =>
          !localFolderIds.contains(f.id) &&
          !protectedFolderIds.contains(f.id));

      await _metadata.update(appMeta);

      onProgress?.call(1.0, 'Storage reconciliation complete!');
      final report = ReconciliationReport(
        orphanedFilesCleaned: orphanedFilesCleaned,
        chunksDeleted: chunksDeleted,
        spaceFreedMb: spaceFreedMb,
        partitionsCleaned: partitionsCleaned,
        cleanedFileNames: cleanedFileNames,
      );

      AppLogger.i(
        'Reconciliation finished: ${report.orphanedFilesCleaned} files cleaned, ${report.chunksDeleted} chunks purged, ${report.spaceFreedMb.toStringAsFixed(1)} MB freed',
        tag: 'StorageReconciler',
      );

      return report;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Storage reconciliation failed: $e',
        tag: 'StorageReconciler',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
