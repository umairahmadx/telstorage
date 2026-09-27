/*
 * File: device_media_picker_sheet.dart
 * Description: Production-grade 1:1 media thumbnail grid bottom sheet with dynamic album
 * switching, paginated asset loading, numbered multi-selection, and long-press media preview.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../../core/theme/app_colors_extension.dart';
import '../../../../core/theme/app_icons.dart';
import 'device_media_album_sheet.dart';
import 'device_media_preview_dialog.dart';
import 'device_media_scanner.dart';
import 'device_picker_bottom_bar.dart';

/// Bottom sheet dialog presenting device photos and videos in a 1:1 square grid.
class DeviceMediaPickerSheet extends StatefulWidget {
  /// Constructs DeviceMediaPickerSheet.
  const DeviceMediaPickerSheet({super.key});

  /// Displays the media picker sheet and yields selected assets on submission.
  static Future<List<AssetEntity>?> show(BuildContext context) {
    return showModalBottomSheet<List<AssetEntity>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DeviceMediaPickerSheet(),
    );
  }

  @override
  State<DeviceMediaPickerSheet> createState() => _DeviceMediaPickerSheetState();
}

class _DeviceMediaPickerSheetState extends State<DeviceMediaPickerSheet> {
  final ScrollController _scrollController = ScrollController();
  List<MediaAlbum> _albums = [];
  MediaAlbum? _currentAlbum;
  final List<AssetEntity> _assets = [];
  final List<AssetEntity> _selectedAssets = [];

  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 0;
  bool _hasMore = true;
  static const int _pageSize = 60;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initPicker();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMoreMedia();
    }
  }

  Future<void> _initPicker() async {
    final granted = await DeviceMediaScanner.requestPermission();
    if (!granted) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }

    final albums = await DeviceMediaScanner.loadAlbums();
    if (!mounted) return;

    if (albums.isEmpty) {
      setState(() {
        _albums = [];
        _isLoading = false;
      });
      return;
    }

    _albums = albums;
    _currentAlbum = albums.first;
    await _loadAlbumPage(0, isInitial: true);
  }

  Future<void> _loadAlbumPage(int page, {bool isInitial = false}) async {
    if (_currentAlbum == null) return;
    if (isInitial) {
      setState(() {
        _isLoading = true;
        _currentPage = 0;
        _assets.clear();
      });
    }

    final newAssets = await DeviceMediaScanner.loadAlbumMedia(
      _currentAlbum!,
      page: page,
      pageSize: _pageSize,
    );

    if (!mounted) return;

    setState(() {
      _assets.addAll(newAssets);
      _currentPage = page;
      _hasMore = newAssets.length >= _pageSize;
      _isLoading = false;
      _isLoadingMore = false;
    });
  }

  Future<void> _loadMoreMedia() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    await _loadAlbumPage(_currentPage + 1);
  }

  void _switchAlbum(MediaAlbum album) {
    if (_currentAlbum?.id == album.id) return;
    setState(() {
      _currentAlbum = album;
    });
    _loadAlbumPage(0, isInitial: true);
  }

  void _toggleSelectAsset(AssetEntity asset) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedAssets.contains(asset)) {
        _selectedAssets.remove(asset);
      } else {
        _selectedAssets.add(asset);
      }
    });
  }

  void _toggleSelectAll() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedAssets.length == _assets.length) {
        _selectedAssets.clear();
      } else {
        _selectedAssets.clear();
        _selectedAssets.addAll(_assets);
      }
    });
  }

  void _openAlbumSelector() {
    DeviceMediaAlbumSheet.show(
      context,
      albums: _albums,
      currentAlbum: _currentAlbum,
      onAlbumSelected: _switchAlbum,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>();
    final sheetHeight = MediaQuery.of(context).size.height * 0.90;

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: colors?.bgPrimary ?? Colors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors?.borderSubtle ?? Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header: Album switcher dropdown + Close button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Material(
                  color: colors?.bgSurfaceInset ?? Colors.white10,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _openAlbumSelector,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppIcons.photoLibrary,
                              color: colors?.accentPrimary, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _currentAlbum != null
                                ? '${_currentAlbum!.name} (${_currentAlbum!.mediaCount})'
                                : 'Select Album',
                            style: TextStyle(
                              color: colors?.textPrimary ?? Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(AppIcons.dropdownArrow,
                              color: colors?.textSecondary, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    icon: Icon(AppIcons.close, color: colors?.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          // Media Grid
          Expanded(
            child: _buildGridContent(colors),
          ),
          // Batch Action Bottom Bar
          DevicePickerBottomBar(
            selectedCount: _selectedAssets.length,
            isAllSelected:
                _assets.isNotEmpty && _selectedAssets.length == _assets.length,
            onToggleSelectAll: _toggleSelectAll,
            onSubmit: () => Navigator.pop(context, _selectedAssets),
          ),
        ],
      ),
    );
  }

  Widget _buildGridContent(AppColorsExtension? colors) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: colors?.accentPrimary),
      );
    }

    if (_assets.isEmpty) {
      return Center(
        child: Text(
          'No photos or videos found',
          style: TextStyle(color: colors?.textSecondary ?? Colors.white54),
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        childAspectRatio: 1.0,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _assets.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _assets.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors?.accentPrimary,
                ),
              ),
            ),
          );
        }

        final asset = _assets[index];
        final selectionIndex = _selectedAssets.indexOf(asset);
        final isSelected = selectionIndex != -1;

        return _MediaTile(
          asset: asset,
          isSelected: isSelected,
          selectionNumber: isSelected ? selectionIndex + 1 : null,
          colors: colors,
          onTap: () => _toggleSelectAsset(asset),
          onLongPress: () => DeviceMediaPreviewDialog.show(context, asset),
        );
      },
    );
  }
}

class _MediaTile extends StatelessWidget {
  final AssetEntity asset;
  final bool isSelected;
  final int? selectionNumber;
  final AppColorsExtension? colors;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MediaTile({
    required this.asset,
    required this.isSelected,
    required this.selectionNumber,
    required this.colors,
    required this.onTap,
    required this.onLongPress,
  });

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = asset.type == AssetType.video;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: asset.thumbnailDataWithSize(
                const ThumbnailSize.square(200),
              ),
              builder: (_, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  );
                }
                return Container(
                  color: colors?.bgSurfaceInset ?? Colors.white10,
                );
              },
            ),
            // Selection dark overlay
            if (isSelected)
              Container(
                color: Colors.black38,
              ),
            // Video duration overlay at bottom
            if (isVideo)
              Positioned(
                bottom: 4,
                left: 4,
                right: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(AppIcons.play, color: Colors.white, size: 12),
                    const SizedBox(width: 2),
                    Text(
                      _formatDuration(asset.duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black87),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            // Selection Badge at top-right
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? (colors?.accentPrimary ?? Colors.blue)
                      : Colors.black38,
                  border: Border.all(
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: isSelected
                      ? Text(
                          '$selectionNumber',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
