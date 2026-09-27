/*
 * File: audio_lyrics_view.dart
 * Description: Apple Music style time-synced auto-scrolling lyrics view with vertical gradient dissolve, interactive tap-to-seek, and timing adjustments.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/models/lyric_line.dart';
import '../../../../../../core/theme/app_icons.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../viewmodel/audio_player_view_model.dart';

/// Fullscreen or embedded synchronized lyrics view styled after Apple Music.
class AudioLyricsView extends StatefulWidget {
  final AudioPlayerViewModel viewModel;

  const AudioLyricsView({
    super.key,
    required this.viewModel,
  });

  @override
  State<AudioLyricsView> createState() => _AudioLyricsViewState();
}

class _AudioLyricsViewState extends State<AudioLyricsView> {
  final ScrollController _scrollController = ScrollController();
  bool _userScrolledAway = false;
  int _lastAutoScrolledIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
  }

  @override
  void didUpdateWidget(covariant AudioLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      widget.viewModel.addListener(_onViewModelChanged);
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    final curIdx = widget.viewModel.currentLyricIndex;
    if (curIdx != _lastAutoScrolledIndex && curIdx >= 0 && !_userScrolledAway) {
      _scrollToIndex(curIdx);
      _lastAutoScrolledIndex = curIdx;
    }
    setState(() {});
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    // Estimate ~56px per line, center in viewport
    final targetOffset = (index * 56.0) - 120.0;
    final clamped = targetOffset.clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clamped,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _reSyncToCurrent() {
    setState(() {
      _userScrolledAway = false;
    });
    final cur = widget.viewModel.currentLyricIndex;
    if (cur >= 0) {
      _scrollToIndex(cur);
      _lastAutoScrolledIndex = cur;
    }
  }

  Widget _buildTopSyncBar(AppColorsExtension colors) {
    final offsetMs = widget.viewModel.lyricsOffset.inMilliseconds;
    final offsetStr = offsetMs > 0 ? '+$offsetMs ms' : (offsetMs < 0 ? '$offsetMs ms' : 'In Sync');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Offset readout and fine-tune buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(AppIcons.skipPrevious, size: 14),
                  tooltip: '-250 ms',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  color: colors.textSecondary,
                  onPressed: () => widget.viewModel.adjustLyricsOffset(const Duration(milliseconds: -250)),
                ),
                GestureDetector(
                  onTap: widget.viewModel.resetLyricsOffset,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      offsetStr,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: offsetMs != 0 ? colors.accentPrimary : colors.textTertiary,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(AppIcons.skipNext, size: 14),
                  tooltip: '+250 ms',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  color: colors.textSecondary,
                  onPressed: () => widget.viewModel.adjustLyricsOffset(const Duration(milliseconds: 250)),
                ),
              ],
            ),
          ),

          // File import & reload
          Row(
            children: [
              IconButton(
                icon: Icon(AppIcons.folderOpen, color: colors.textSecondary, size: 18),
                tooltip: 'Load .lrc file from storage',
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: widget.viewModel.pickLocalLyrics,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(AppIcons.refresh, color: colors.textSecondary, size: 18),
                tooltip: 'Reload lyrics online',
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: widget.viewModel.loadLyricsForCurrentTrack,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsList(List<LyricLine> lyrics, AppColorsExtension colors) {
    return NotificationListener<UserScrollNotification>(
      onNotification: (notification) {
        if (!_userScrolledAway) {
          setState(() {
            _userScrolledAway = true;
          });
        }
        return false;
      },
      child: ShaderMask(
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0.0, 0.12, 0.88, 1.0],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 90),
          physics: const BouncingScrollPhysics(),
          itemCount: lyrics.length,
          itemBuilder: (context, index) {
            final line = lyrics[index];
            final isActive = index == widget.viewModel.currentLyricIndex;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => widget.viewModel.seekToLyric(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      fontSize: isActive ? 22 : 17,
                      fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                      color: isActive
                          ? colors.accentPrimary
                          : colors.textPrimary.withValues(alpha: 0.38),
                      height: 1.35,
                      letterSpacing: isActive ? -0.2 : 0.0,
                    ),
                    child: Text(
                      line.text.isEmpty ? '♪' : line.text,
                      textAlign: TextAlign.left,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppColorsExtension colors) {
    if (widget.viewModel.isLoadingLyrics) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colors.accentPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Searching synced lyrics...',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.subtitles, size: 48, color: colors.textTertiary),
            const SizedBox(height: 12),
            Text(
              'No Synced Lyrics Found',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'You can import a local .lrc file or retry search.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(AppIcons.folderOpen, size: 16),
                  label: const Text('Import .lrc'),
                  onPressed: widget.viewModel.pickLocalLyrics,
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(AppIcons.refresh, size: 16),
                  label: const Text('Retry'),
                  onPressed: widget.viewModel.loadLyricsForCurrentTrack,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lyrics = widget.viewModel.lyrics;

    return Stack(
      children: [
        Column(
          children: [
            _buildTopSyncBar(colors),
            Expanded(
              child: lyrics.isEmpty
                  ? _buildEmptyState(colors)
                  : _buildLyricsList(lyrics, colors),
            ),
          ],
        ),

        // Floating sync button if user scrolled away
        if (_userScrolledAway && lyrics.isNotEmpty)
          Positioned(
            bottom: 12,
            right: 20,
            child: Material(
              color: colors.accentPrimary,
              borderRadius: BorderRadius.circular(20),
              elevation: 4,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _reSyncToCurrent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.play, color: colors.bgPrimary, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        'Sync',
                        style: TextStyle(
                          color: colors.bgPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
