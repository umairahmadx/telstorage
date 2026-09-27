/*
 * File: device_media_preview_dialog.dart
 * Description: Fullscreen preview dialog for photos and videos selected in the media picker,
 * supporting pinch-to-zoom for photos and in-place playback for videos.
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_view/photo_view.dart';
import '../../../../core/theme/app_colors_extension.dart';
import '../../../../core/theme/app_icons.dart';
import 'device_media_scanner.dart';

/// Modal dialog displaying high-resolution image zoom or video playback for an AssetEntity.
class DeviceMediaPreviewDialog extends StatefulWidget {
  /// The asset entity to preview.
  final AssetEntity asset;

  /// Constructs DeviceMediaPreviewDialog.
  const DeviceMediaPreviewDialog({super.key, required this.asset});

  /// Presents the preview dialog above the current route.
  static void show(BuildContext context, AssetEntity asset) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      useSafeArea: false,
      builder: (_) => DeviceMediaPreviewDialog(asset: asset),
    );
  }

  @override
  State<DeviceMediaPreviewDialog> createState() =>
      _DeviceMediaPreviewDialogState();
}

class _DeviceMediaPreviewDialogState extends State<DeviceMediaPreviewDialog> {
  String? _filePath;
  bool _isLoading = true;
  String? _errorMessage;

  Player? _player;
  VideoController? _videoController;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    try {
      final (path, _) =
          await DeviceMediaScanner.resolveUploadPath(widget.asset);
      if (!mounted) return;

      setState(() {
        _filePath = path;
        _isLoading = false;
      });

      if (widget.asset.type == AssetType.video) {
        final p = Player();
        final vc = VideoController(p);
        _player = p;
        _videoController = vc;
        await p.open(Media(path), play: true);
        if (!mounted) return;
        setState(() {});
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();
    final isVideo = widget.asset.type == AssetType.video;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Center(
            child: _buildBody(colors, isVideo),
          ),
          // Top bar with close button and file title
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.asset.title ?? 'Media Preview',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    icon: const Icon(AppIcons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
          // Bottom metadata overlay
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isVideo ? AppIcons.fileVideo : AppIcons.fileImage,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isVideo
                            ? 'Video • ${_formatDuration(widget.asset.duration)} • ${widget.asset.width}x${widget.asset.height}'
                            : 'Photo • ${widget.asset.width}x${widget.asset.height}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppColorsExtension? colors, bool isVideo) {
    if (_isLoading) {
      return CircularProgressIndicator(color: colors?.accentPrimary);
    }

    if (_errorMessage != null || _filePath == null) {
      return Text(
        _errorMessage ?? 'Unable to preview media',
        style: TextStyle(color: colors?.error ?? Colors.red),
      );
    }

    if (isVideo && _videoController != null) {
      return GestureDetector(
        onTap: () {
          if (_player != null) {
            _player!.playOrPause();
            setState(() {
              _isPlaying = !_isPlaying;
            });
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Video(controller: _videoController!),
            if (!_isPlaying)
              Container(
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: const Icon(
                  AppIcons.play,
                  color: Colors.white,
                  size: 48,
                ),
              ),
          ],
        ),
      );
    }

    return PhotoView(
      imageProvider: FileImage(File(_filePath!)),
      backgroundDecoration: const BoxDecoration(color: Colors.transparent),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 3.0,
    );
  }
}
