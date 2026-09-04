/*
 * File: browser_partition_helper.dart
 * Description: Helper handling directory partition verification and on-demand synchronization for BrowserBloc.
 */

import 'package:telstorage/core/constants/app_constants.dart';
import 'package:telstorage/core/services/service_locator.dart';

/// Helper methods for verifying and synchronizing folder partitions.
abstract final class BrowserPartitionHelper {
  /// Checks partition status and syncs from cloud if connected.
  /// Returns `true` if directory should be loaded from local cache,
  /// or `false` if the folder is uncached and offline.
  static Future<bool> ensureDirectoryPartitionReady({
    required String? folderId,
    required bool isOffline,
  }) async {
    final partitionId = folderId ?? AppConstants.rootFolderPartitionId;
    final isCached = ServiceLocator.instance.isInitialized &&
        ServiceLocator.instance.hive.getFolderPartitionMessageId(partitionId) !=
            null;

    if (isOffline) {
      return isCached;
    }

    try {
      if (ServiceLocator.instance.isInitialized) {
        await ServiceLocator.instance.syncService
            .syncFolderPartition(partitionId);
        return true;
      }
      return false;
    } catch (_) {
      return isCached;
    }
  }
}
