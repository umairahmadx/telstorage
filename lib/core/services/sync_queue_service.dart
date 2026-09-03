/*
 * File: sync_queue_service.dart
 * Description: Component and logic definition for sync_queue_service.dart in TelStorage.
 */

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../constants/app_constants.dart';
import '../models/pending_action.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import 'file_manager.dart';
import 'telegram_rate_limiter.dart';

class SyncLogItem {
  final String id;
  final String actionType;
  final String description;
  final DateTime timestamp;
  final String status; // 'pending', 'syncing', 'completed', 'failed'
  final String? error;

  SyncLogItem({
    required this.id,
    required this.actionType,
    required this.description,
    required this.timestamp,
    required this.status,
    this.error,
  });
}

class SyncQueueService {
  final FileManagerService _fileManager;
  bool _isProcessing = false;
  Timer? _periodicTimer;
  int _failureCount = 0;
  DateTime? _nextAllowedRun;

  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<List<SyncLogItem>> logsNotifier =
      ValueNotifier<List<SyncLogItem>>([]);

  /// Whether exponential backoff is actively throttling queue retries.
  bool get isBackoffActive =>
      _nextAllowedRun != null && DateTime.now().isBefore(_nextAllowedRun!);

  /// Remaining duration of the exponential backoff pause, or [Duration.zero].
  Duration get remainingBackoff => isBackoffActive
      ? _nextAllowedRun!.difference(DateTime.now())
      : Duration.zero;

  /// Reset consecutive failure backoff state.
  void resetBackoff() {
    _failureCount = 0;
    _nextAllowedRun = null;
  }

  SyncQueueService(this._fileManager) {
    _updatePendingCount();
    _periodicTimer = Timer.periodic(
      const Duration(seconds: AppConstants.syncIntervalSeconds),
      (_) {
        if (pendingCount > 0 && !_isProcessing) {
          processQueue();
        }
      },
    );
  }

  void dispose() {
    _periodicTimer?.cancel();
  }

  Box<PendingAction> get _pendingBox =>
      Hive.box<PendingAction>(AppConstants.pendingActionsBox);

  bool get isProcessing => _isProcessing;
  int get pendingCount => _pendingBox.length;

  void _updatePendingCount() {
    pendingCountNotifier.value = _pendingBox.length;
  }

  void clearLogs() {
    logsNotifier.value = [];
  }

  Future<void> processQueue({bool force = false}) async {
    _updatePendingCount();
    if (_isProcessing) return;
    if (pendingCount == 0) return;

    if (force) {
      resetBackoff();
    }

    if (TelegramRateLimiter.instance.isPaused) {
      final waitMs =
          TelegramRateLimiter.instance.remainingCooldown.inMilliseconds;
      AppLogger.w(
        'SyncQueue: cannot process, Telegram rate limit backoff active (${waitMs}ms remaining).',
        tag: 'SyncQueue',
      );
      return;
    }

    if (isBackoffActive) {
      AppLogger.d(
        'SyncQueue: exponential backoff active (${remainingBackoff.inMilliseconds}ms remaining), skipping processing.',
        tag: 'SyncQueue',
      );
      return;
    }

    if (!await Connectivity.hasConnection()) {
      AppLogger.d('SyncQueue: cannot process, device is offline.',
          tag: 'SyncQueue');
      return;
    }

    _isProcessing = true;
    AppLogger.i('SyncQueue: starting processing of $pendingCount actions...',
        tag: 'SyncQueue');

    try {
      final actions = _pendingBox.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      for (final action in actions) {
        // If a 429 backoff was activated by a prior action in this batch, stop immediately
        if (TelegramRateLimiter.instance.isPaused) {
          AppLogger.w(
            'SyncQueue: Telegram 429 encountered during batch, pausing queue.',
            tag: 'SyncQueue',
          );
          break;
        }

        AppLogger.d(
            'SyncQueue: processing action ${action.actionType} (${action.id})',
            tag: 'SyncQueue');
        final desc = _getActionDescription(action);

        final syncingLog = SyncLogItem(
          id: action.id,
          actionType: action.actionType,
          description: desc,
          timestamp: DateTime.now(),
          status: 'syncing',
        );
        logsNotifier.value = [
          syncingLog,
          ...logsNotifier.value.where((l) => l.id != action.id)
        ];

        try {
          await _executeAction(action);
          await _pendingBox.delete(action.id);
          _updatePendingCount();

          // Reset backoff on successful execution
          _failureCount = 0;
          _nextAllowedRun = null;

          final completedLog = SyncLogItem(
            id: action.id,
            actionType: action.actionType,
            description: desc,
            timestamp: DateTime.now(),
            status: 'completed',
          );
          logsNotifier.value = [
            completedLog,
            ...logsNotifier.value.where((l) => l.id != action.id)
          ];

          AppLogger.d(
              'SyncQueue: successfully processed & deleted action ${action.id}',
              tag: 'SyncQueue');
        } catch (e) {
          _failureCount++;
          final backoffSeconds =
              math.min(300, (1 << math.min(_failureCount, 5)) * 5); // 10s, 20s, 40s, 80s, 160s, max 300s
          _nextAllowedRun =
              DateTime.now().add(Duration(seconds: backoffSeconds));

          AppLogger.e('SyncQueue: failed to process action ${action.id}: $e',
              tag: 'SyncQueue', error: e);
          final failedLog = SyncLogItem(
            id: action.id,
            actionType: action.actionType,
            description: desc,
            timestamp: DateTime.now(),
            status: 'failed',
            error: e.toString(),
          );
          logsNotifier.value = [
            failedLog,
            ...logsNotifier.value.where((l) => l.id != action.id)
          ];

          if (e.toString().contains('not empty') ||
              e.toString().contains('FolderNotEmptyException')) {
            await _pendingBox.delete(action.id);
            _updatePendingCount();
          }
          break;
        }
      }
    } finally {
      _isProcessing = false;
      _updatePendingCount();
      AppLogger.i('SyncQueue: processing finished.', tag: 'SyncQueue');
    }
  }

  String _getActionDescription(PendingAction action) {
    final payload = action.payload;
    switch (action.actionType) {
      case AppConstants.actionCreateFolder:
        return 'Created folder "${payload['name']}"';
      case AppConstants.actionRenameFolder:
        return 'Renamed folder to "${payload['name']}"';
      case AppConstants.actionMoveFolder:
        return 'Moved folder';
      case AppConstants.actionDeleteFolder:
        return 'Deleted folder';
      case AppConstants.actionRenameFile:
        return 'Renamed file to "${payload['name']}"';
      case AppConstants.actionMoveFile:
        return 'Moved file';
      case AppConstants.actionCopyFile:
        return 'Copied file';
      case AppConstants.actionDeleteFile:
        return 'Deleted file';
      case AppConstants.actionAddFileMeta:
        final name = (payload['fileMeta'] is Map)
            ? (payload['fileMeta']['name'] ?? '')
            : '';
        return 'Synced metadata for "$name"';
      default:
        return action.actionType;
    }
  }

  Future<void> _executeAction(PendingAction action) async {
    final payload = action.payload;

    switch (action.actionType) {
      case AppConstants.actionAddFileMeta:
        final fileMeta = Map<String, dynamic>.from(payload['fileMeta'] as Map);
        final metaService = _fileManager.metadataService;
        final appMeta = await metaService.fetch();
        await metaService.addFile(appMeta, fileMeta);
        break;

      case AppConstants.actionCreateFolder:
        final id = payload['id'] as String;
        final name = payload['name'] as String;
        final parentId = payload['parentId'] as String?;
        await _fileManager.createFolder(name, parentId: parentId, folderId: id);
        break;

      case AppConstants.actionRenameFolder:
        final folderId = payload['folderId'] as String;
        final name = payload['name'] as String;
        await _fileManager.renameFolder(folderId, name);
        break;

      case AppConstants.actionMoveFolder:
        final folderId = payload['folderId'] as String;
        final parentId = payload['parentId'] as String?;
        await _fileManager.moveFolder(folderId, parentId);
        break;

      case AppConstants.actionDeleteFolder:
        final folderId = payload['folderId'] as String;
        final folderIds = (payload['folderIds'] as List? ?? const [])
            .map((id) => id.toString())
            .toList();
        final snapshots = (payload['fileSnapshots'] as List? ?? const [])
            .map((snapshot) => Map<String, dynamic>.from(snapshot as Map))
            .toList();
        await _fileManager.deleteFolder(
          folderId,
          folderIds: folderIds,
          fileSnapshots: snapshots,
        );
        break;

      case AppConstants.actionRenameFile:
        final fileId = payload['fileId'] as String;
        final name = payload['name'] as String;
        await _fileManager.renameFile(fileId, name);
        break;

      case AppConstants.actionMoveFile:
        final fileId = payload['fileId'] as String;
        final folderId = payload['folderId'] as String?;
        await _fileManager.moveFile(fileId, folderId);
        break;

      case AppConstants.actionCopyFile:
        final originalFileId =
            (payload['originalFileId'] ?? payload['fileId']) as String;
        final newFileId = payload['newFileId'] as String?;
        final newName = payload['newName'] as String?;
        final targetFolderId = payload['targetFolderId'] as String?;
        if (newFileId != null && newName != null) {
          await _fileManager.copyFile(
            originalFileId: originalFileId,
            newFileId: newFileId,
            newName: newName,
            targetFolderId: targetFolderId,
          );
        }
        break;

      case AppConstants.actionDeleteFile:
        final fileId = payload['fileId'] as String;
        final metadataMessageId = payload['metadataMessageId'] as int?;
        final metadataFileId = payload['metadataFileId'] as String?;
        final sizeMb = (payload['sizeMb'] as num?)?.toDouble() ?? 0.0;
        final mimeType =
            (payload['mimeType'] as String?) ?? 'application/octet-stream';
        final folderId = payload['folderId'] as String?;
        await _fileManager.deleteFileRemoteOnly(
          fileId: fileId,
          metadataMessageId: metadataMessageId,
          metadataFileId: metadataFileId,
          sizeMb: sizeMb,
          mimeType: mimeType,
          folderId: folderId,
        );
        break;

      default:
        throw Exception('Unknown action type: ${action.actionType}');
    }
  }
}
