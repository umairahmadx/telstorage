/*
 * File: browser_mutation_helper.dart
 * Description: Helper functions executing file and folder CRUD mutation commands for BrowserBloc.
 */

import 'package:telstorage/core/services/service_locator.dart';
import 'package:telstorage/features/storage/domain/repositories/storage_repository_contract.dart';

/// Helper methods executing single-item mutations for BrowserBloc.
abstract final class BrowserMutationHelper {
  /// Creates a folder.
  static Future<String?> createFolder({
    required String name,
    required String? parentId,
    required StorageRepositoryContract repository,
  }) async {
    final res = await repository.createFolder(name, parentId: parentId);
    return res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        return null;
      },
      (failure) => failure.message,
    );
  }

  /// Renames a folder.
  static Future<String?> renameFolder({
    required String folderId,
    required String newName,
    required StorageRepositoryContract repository,
  }) async {
    final res = await repository.renameFolder(folderId, newName);
    return res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        return null;
      },
      (failure) => failure.message,
    );
  }

  /// Deletes a folder.
  static Future<String?> deleteFolder({
    required String folderId,
    required StorageRepositoryContract repository,
  }) async {
    final res = await repository.deleteFolder(folderId);
    return res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        return null;
      },
      (failure) => failure.message,
    );
  }

  /// Renames a file.
  static Future<String?> renameFile({
    required String fileId,
    required String newName,
    required StorageRepositoryContract repository,
  }) async {
    final res = await repository.renameFile(fileId, newName);
    return res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        return null;
      },
      (failure) => failure.message,
    );
  }

  /// Moves a single file.
  static Future<void> moveFile({
    required String fileId,
    required String? targetFolderId,
    required StorageRepositoryContract repository,
  }) async {
    await repository.moveFile(fileId, targetFolderId);
    ServiceLocator.instance.syncQueue.processQueue();
  }

  /// Copies a single file.
  static Future<String?> copyFile({
    required String fileId,
    required String? targetFolderId,
    required StorageRepositoryContract repository,
  }) async {
    final res = await repository.copyFile(fileId, targetFolderId);
    return res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        return null;
      },
      (failure) => failure.message,
    );
  }

  /// Deletes a single file.
  static Future<String?> deleteFile({
    required String fileId,
    required StorageRepositoryContract repository,
  }) async {
    final res = await repository.deleteFile(fileId);
    return res.fold(
      (_) {
        ServiceLocator.instance.syncQueue.processQueue();
        return null;
      },
      (failure) => failure.message,
    );
  }
}
