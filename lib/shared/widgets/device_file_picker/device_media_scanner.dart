/*
 * File: device_media_scanner.dart
 * Description: Zero-copy data layer wrapping photo_manager to query Android MediaStore
 * for dynamic albums, paginated media assets, and direct POSIX upload path resolution.
 */

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// Lightweight model representing a device media album from the OS MediaStore.
class MediaAlbum {
  /// Unique album identifier from the OS.
  final String id;

  /// Human-readable album name (e.g. "Camera", "Screenshots", "WhatsApp").
  final String name;

  /// Total media item count in this album.
  final int mediaCount;

  /// Underlying photo_manager path entity for paginated asset fetching.
  /// Null only in unit test contexts.
  final AssetPathEntity? pathEntity;

  /// Constructs MediaAlbum.
  const MediaAlbum({
    required this.id,
    required this.name,
    required this.mediaCount,
    required this.pathEntity,
  });
}

/// Data-only service wrapping photo_manager for zero-copy media access.
/// Never calls asset.file on Android — resolves direct POSIX paths instead.
class DeviceMediaScanner {
  /// Default storage root on Android.
  static const String _androidStorageRoot = '/storage/emulated/0/';

  /// Requests photo library permission and returns whether granted.
  static Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    final state = await PhotoManager.requestPermissionExtend();
    return state.isAuth || state.hasAccess;
  }

  /// Loads all dynamic albums from the OS MediaStore.
  /// Returns albums sorted by media count descending, with "Recent" first.
  static Future<List<MediaAlbum>> loadAlbums() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
    );

    final albums = <MediaAlbum>[];
    for (final path in paths) {
      final count = await path.assetCountAsync;
      if (count == 0) continue;
      albums.add(MediaAlbum(
        id: path.id,
        name: path.name,
        mediaCount: count,
        pathEntity: path,
      ));
    }

    albums.sort((a, b) {
      final aIsAll = a.pathEntity?.isAll ?? false;
      final bIsAll = b.pathEntity?.isAll ?? false;
      if (aIsAll && !bIsAll) return -1;
      if (!aIsAll && bIsAll) return 1;
      return b.mediaCount.compareTo(a.mediaCount);
    });

    return albums;
  }

  /// Loads a paginated slice of media assets from the given album.
  /// Uses page-based loading to keep RAM bounded (~60 assets at a time).
  static Future<List<AssetEntity>> loadAlbumMedia(
    MediaAlbum album, {
    int page = 0,
    int pageSize = 60,
  }) async {
    if (album.pathEntity == null) return [];
    return album.pathEntity!.getAssetListPaged(
      page: page,
      size: pageSize,
    );
  }

  /// Resolves the zero-copy upload path for an AssetEntity.
  /// On Android: constructs direct POSIX path from MediaStore metadata.
  /// On iOS: retrieves sandbox file and marks as temporary for cleanup.
  static Future<(String path, bool isTemporary)> resolveUploadPath(
    AssetEntity asset,
  ) async {
    if (!kIsWeb && Platform.isAndroid) {
      final directPath = constructDirectPath(
        relativePath: asset.relativePath ?? '',
        title: asset.title ?? 'file',
      );
      if (File(directPath).existsSync()) {
        return (directPath, false);
      }

      final file = await asset.originFile;
      if (file != null) {
        return (file.path, isTemporaryPath(file.path));
      }

      throw StateError('Cannot resolve upload path for asset ${asset.id}');
    } else {
      final file = await asset.originFile;
      if (file == null) {
        throw StateError('Cannot access file for asset ${asset.id}');
      }
      return (file.path, true);
    }
  }

  /// Constructs the direct Android storage path from MediaStore metadata.
  /// Visible for testing.
  @visibleForTesting
  static String constructDirectPath({
    required String relativePath,
    required String title,
  }) {
    return '$_androidStorageRoot$relativePath$title';
  }

  /// Determines if a resolved path points to a temporary cache location.
  /// Visible for testing.
  @visibleForTesting
  static bool isTemporaryPath(String path) {
    return path.contains('/cache/') ||
        path.contains('/tmp/') ||
        path.contains('/Containers/Data/');
  }
}
