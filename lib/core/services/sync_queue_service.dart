import 'package:hive/hive.dart';
import '../constants/app_constants.dart';
import '../models/pending_action.dart';
import '../utils/app_logger.dart';
import '../utils/connectivity.dart';
import 'file_manager.dart';

class SyncQueueService {
  final FileManagerService _fileManager;
  bool _isProcessing = false;

  SyncQueueService(this._fileManager);

  Box<PendingAction> get _pendingBox =>
      Hive.box<PendingAction>(AppConstants.pendingActionsBox);

  bool get isProcessing => _isProcessing;
  int get pendingCount => _pendingBox.length;

  Future<void> processQueue() async {
    if (_isProcessing) return;
    if (pendingCount == 0) return;

    if (!await Connectivity.hasConnection()) {
      AppLogger.d('SyncQueue: cannot process, device is offline.', tag: 'SyncQueue');
      return;
    }

    _isProcessing = true;
    AppLogger.i('SyncQueue: starting processing of $pendingCount actions...', tag: 'SyncQueue');

    try {
      // Get actions sorted by timestamp/insertion order
      final actions = _pendingBox.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      for (final action in actions) {
        AppLogger.d('SyncQueue: processing action ${action.actionType} (${action.id})', tag: 'SyncQueue');
        try {
          await _executeAction(action);
          await _pendingBox.delete(action.id);
          AppLogger.d('SyncQueue: successfully processed & deleted action ${action.id}', tag: 'SyncQueue');
        } catch (e) {
          AppLogger.e('SyncQueue: failed to process action ${action.id}: $e', tag: 'SyncQueue', error: e);
          // If it's a structural or critical issue (e.g. folder not empty on remote but we deleted it locally),
          // we might want to skip it to avoid getting stuck forever.
          // For now, we continue to the next one, but keep the failing one to retry or report.
          // Let's remove it if it's a FolderNotEmptyException, or retry later.
          if (e.toString().contains('not empty') || e.toString().contains('FolderNotEmptyException')) {
            await _pendingBox.delete(action.id);
          }
          break; // Stop processing the rest of the queue for safety
        }
      }
    } finally {
      _isProcessing = false;
      AppLogger.i('SyncQueue: processing finished.', tag: 'SyncQueue');
    }
  }

  Future<void> _executeAction(PendingAction action) async {
    final payload = action.payload;

    switch (action.actionType) {
      case 'createFolder':
        final id = payload['id'] as String;
        final name = payload['name'] as String;
        final parentId = payload['parentId'] as String?;
        await _fileManager.createFolder(name, parentId: parentId, folderId: id);
        break;

      case 'renameFolder':
        final folderId = payload['folderId'] as String;
        final name = payload['name'] as String;
        await _fileManager.renameFolder(folderId, name);
        break;

      case 'deleteFolder':
        final folderId = payload['folderId'] as String;
        await _fileManager.deleteFolder(folderId);
        break;

      case 'renameFile':
        final fileId = payload['fileId'] as String;
        final name = payload['name'] as String;
        await _fileManager.renameFile(fileId, name);
        break;

      case 'moveFile':
        final fileId = payload['fileId'] as String;
        final folderId = payload['folderId'] as String?;
        await _fileManager.moveFile(fileId, folderId);
        break;

      case 'copyFile':
        final fileId = payload['fileId'] as String;
        final targetFolderId = payload['targetFolderId'] as String?;
        await _fileManager.copyFile(fileId, targetFolderId);
        break;

      case 'deleteFile':
        final fileId = payload['fileId'] as String;
        final metadataMessageId = payload['metadataMessageId'] as int;
        final metadataFileId = payload['metadataFileId'] as String?;
        final sizeMb = (payload['sizeMb'] as num).toDouble();
        final mimeType = payload['mimeType'] as String;
        await _fileManager.deleteFileRemoteOnly(
          fileId: fileId,
          metadataMessageId: metadataMessageId,
          metadataFileId: metadataFileId,
          sizeMb: sizeMb,
          mimeType: mimeType,
        );
        break;

      default:
        throw Exception('Unknown action type: ${action.actionType}');
    }
  }
}
