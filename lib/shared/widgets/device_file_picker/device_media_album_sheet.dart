/*
 * File: device_media_album_sheet.dart
 * Description: Bottom sheet modal for selecting media albums from the OS MediaStore.
 */

import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors_extension.dart';
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
                      title: Text(
                        album.name,
                        style: TextStyle(
                          color: isSelected
                              ? (colors?.accentPrimary ?? Colors.blue)
                              : (colors?.textPrimary ?? Colors.white),
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      trailing: Text(
                        '${album.mediaCount}',
                        style: TextStyle(
                          color: colors?.textSecondary ?? Colors.white54,
                          fontSize: 13,
                        ),
                      ),
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
