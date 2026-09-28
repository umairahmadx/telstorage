/*
 * File: device_media_album_sheet.dart
 * Description: Bottom sheet modal for selecting media albums from the OS MediaStore,
 * presenting the most recent asset thumbnail for each folder.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_colors_extension.dart';
import '../../../../core/theme/app_icons.dart';
import 'device_media_scanner.dart';

/// Bottom sheet dialog listing all device media albums for user selection.
class DeviceMediaAlbumSheet extends StatelessWidget {
  /// List of available albums.
  final List<MediaAlbum> albums;

  /// Currently selected album.
  final MediaAlbum? currentAlbum;

  /// Callback when an album is selected.
  final ValueChanged<MediaAlbum> onAlbumSelected;

  /// Constructs DeviceMediaAlbumSheet.
  const DeviceMediaAlbumSheet({
    super.key,
    required this.albums,
    required this.currentAlbum,
    required this.onAlbumSelected,
  });

  /// Displays the album selector modal sheet.
  static void show(
    BuildContext context, {
    required List<MediaAlbum> albums,
    required MediaAlbum? currentAlbum,
    required ValueChanged<MediaAlbum> onAlbumSelected,
  }) {
    final colors = Theme.of(context).extension<AppColorsExtension>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors?.bgSurface ?? Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors?.borderSubtle ?? Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Select Album',
                  style: TextStyle(
                    color: colors?.textPrimary ?? Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: albums.length,
                  itemBuilder: (_, index) {
                    final album = albums[index];
                    final isSelected = album.id == currentAlbum?.id;
                    return ListTile(
                      leading: _AlbumThumbnail(
                        pathEntity: album.pathEntity,
                        colors: colors,
                      ),
                      title: Text(
                        album.name,
                        style: TextStyle(
                          color: isSelected
                              ? (colors?.brandPrimary ?? AppColors.primary)
                              : (colors?.textPrimary ?? Colors.white),
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        '${album.mediaCount} items',
                        style: TextStyle(
                          color: colors?.textSecondary ?? Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              AppIcons.check,
                              color: colors?.brandPrimary ?? AppColors.primary,
                              size: 20,
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        onAlbumSelected(album);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _AlbumThumbnail extends StatefulWidget {
  final AssetPathEntity? pathEntity;
  final AppColorsExtension? colors;

  const _AlbumThumbnail({
    required this.pathEntity,
    required this.colors,
  });

  @override
  State<_AlbumThumbnail> createState() => _AlbumThumbnailState();
}

class _AlbumThumbnailState extends State<_AlbumThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (widget.pathEntity == null) return;
    try {
      final assets =
          await widget.pathEntity!.getAssetListRange(start: 0, end: 1);
      if (assets.isNotEmpty && mounted) {
        final data = await assets.first
            .thumbnailDataWithSize(const ThumbnailSize.square(120));
        if (mounted) {
          setState(() {
            _bytes = data;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 44,
        color: widget.colors?.bgSurfaceInset ?? Colors.white10,
        child: _bytes != null
            ? Image.memory(
                _bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
            : Center(
                child: Icon(
                  AppIcons.photoLibrary,
                  size: 20,
                  color: widget.colors?.textTertiary ?? Colors.white38,
                ),
              ),
      ),
    );
  }
}
