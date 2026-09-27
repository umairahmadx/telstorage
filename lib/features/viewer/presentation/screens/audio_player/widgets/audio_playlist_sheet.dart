/*
 * File: audio_playlist_sheet.dart
 * Description: Modal bottom sheet for viewing and switching tracks within the active audio playlist.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../viewmodel/audio_player_view_model.dart';

/// Modal sheet displaying the active audio playlist tracks.
class AudioPlaylistSheet extends StatelessWidget {
  final AudioPlayerViewModel viewModel;

  const AudioPlaylistSheet({super.key, required this.viewModel});

  static void show(BuildContext context, AudioPlayerViewModel viewModel) {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: colors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AudioPlaylistSheet(viewModel: viewModel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Playlist (${viewModel.playlist.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: Icon(AppIcons.close, color: colors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: viewModel.playlist.length,
                itemBuilder: (context, idx) {
                  final item = viewModel.playlist[idx];
                  final isCurrent = idx == viewModel.currentIndex;
                  return ListTile(
                    leading: Icon(
                      isCurrent ? AppIcons.play : AppIcons.fileAudio,
                      color: isCurrent ? colors.accentPrimary : colors.textSecondary,
                    ),
                    title: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                        color: isCurrent ? colors.accentPrimary : colors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      item.formattedSize,
                      style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      viewModel.selectTrack(idx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
