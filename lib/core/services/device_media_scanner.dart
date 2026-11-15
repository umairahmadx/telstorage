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

  /// Checks photo library authorization without displaying a permission prompt.
  static Future<bool> hasPermission() async {
    if (kIsWeb) return false;
    final state = await PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(),
    );
    return state.isAuth || state.hasAccess;
  }

  /// Loads all dynamic albums from the OS MediaStore.
  /// Returns albums sorted by media count descending, with "Recent" first.
  static Future<List<MediaAlbum>> loadAlbums() async {
    final filterOption = FilterOptionGroup(
      orders: [
        const OrderOption(
          type: OrderOptionType.createDate,
          asc: false,
        ),
      ],
    );

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      hasAll: true,
      filterOption: filterOption,
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
  /// Falls back to originFile, and if unavailable, asset.file (marked temporary).
  static Future<(String path, bool isTemporary)> resolveUploadPath(
    AssetEntity asset,
  ) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final directPath = constructDirectPath(
          relativePath: asset.relativePath ?? '',
          title: asset.title ?? 'file',
        );
        final file = File(directPath);
        if (file.existsSync()) {
          try {
            final raf = file.openSync(mode: FileMode.read);
            raf.closeSync();
            return (directPath, false);
          } catch (_) {}
        }
      } catch (_) {}

      try {
        final origin = await asset.originFile;
        if (origin != null && origin.existsSync()) {
          return (origin.path, isTemporaryPath(origin.path));
        }
      } catch (_) {}

      try {
        final fallback = await asset.file;
        if (fallback != null && fallback.existsSync()) {
          return (fallback.path, true);
        }
      } catch (_) {}

      throw StateError('Cannot resolve upload path for asset ${asset.id}');
    } else {
      try {
        final origin = await asset.originFile;
        if (origin != null && origin.existsSync()) {
          return (origin.path, isTemporaryPath(origin.path));
        }
      } catch (_) {}

      try {
        final fallback = await asset.file;
        if (fallback != null && fallback.existsSync()) {
          return (fallback.path, true);
        }
      } catch (_) {}

      throw StateError('Cannot access file for asset ${asset.id}');
    }
  }

  /// Constructs the direct Android storage path from MediaStore metadata.
  /// Visible for testing.
  @visibleForTesting
  static String constructDirectPath({
    required String relativePath,
    required String title,
  }) {
    var rel = relativePath.trim();
    while (rel.startsWith('/')) {
      rel = rel.substring(1);
    }
    if (rel.isNotEmpty && !rel.endsWith('/')) {
      rel = '$rel/';
    }
    final cleanTitle = title.trim();
    return '$_androidStorageRoot$rel$cleanTitle';
  }

  /// Resolves direct POSIX path from preserved asset metadata if readable.
  static ({String path, bool isTemporary})? resolveFastDirectPath({
    required String? relativePath,
    required String title,
  }) {
    if (kIsWeb || !Platform.isAndroid || title.trim().isEmpty) return null;
    try {
      final directPath = constructDirectPath(
        relativePath: relativePath ?? '',
        title: title,
      );
      final file = File(directPath);
      if (file.existsSync()) {
        try {
          final raf = file.openSync(mode: FileMode.read);
          raf.closeSync();
          return (path: directPath, isTemporary: false);
        } catch (_) {}
      }
    } catch (_) {}
    return null;
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
