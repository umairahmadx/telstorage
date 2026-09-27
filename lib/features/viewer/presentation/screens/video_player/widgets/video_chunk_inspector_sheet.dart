/*
 * File: video_chunk_inspector_sheet.dart
 * Description: Real-time inspector bottom sheet displaying chunk caching state, active downloading progress, and streaming metrics.
 */

import 'package:flutter/material.dart';
import '../../../../../../core/services/video_chunk_cache_manager.dart';
import '../../../../../../core/services/video_stream_server.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../viewmodel/video_player_view_model.dart';

/// Modal bottom sheet providing a real-time visual inspector of video chunk caching and streaming activity.
class VideoChunkInspectorSheet extends StatefulWidget {
  final VideoPlayerViewModel viewModel;

  const VideoChunkInspectorSheet({
    super.key,
    required this.viewModel,
  });

  /// Displays the chunk inspector sheet.
  static void show(BuildContext context, {required VideoPlayerViewModel viewModel}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VideoChunkInspectorSheet(viewModel: viewModel),
    );
  }

  @override
  State<VideoChunkInspectorSheet> createState() => _VideoChunkInspectorSheetState();
}

class _VideoChunkInspectorSheetState extends State<VideoChunkInspectorSheet> {
  @override
  void initState() {
    super.initState();
    VideoChunkCacheManager.instance.chunkChangeNotifier.addListener(_onUpdate);
    try {
      VideoStreamServer.instance.prefetchCoordinator.prefetchProgressNotifier
          .addListener(_onUpdate);
    } catch (_) {}
  }

  @override
  void dispose() {
    VideoChunkCacheManager.instance.chunkChangeNotifier.removeListener(_onUpdate);
    try {
      VideoStreamServer.instance.prefetchCoordinator.prefetchProgressNotifier
          .removeListener(_onUpdate);
    } catch (_) {}
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final vm = widget.viewModel;
    final file = vm.currentFile;
    final totalChunks = vm.totalChunks;
    final cached = vm.cachedChunks;
    final inFlight = file != null
        ? VideoStreamServer.instance.prefetchCoordinator.getInFlightFractions(file.fileId)
        : const <int, double>{};

    final cachedCount = cached.length;
    final percent = totalChunks > 0 ? (cachedCount / totalChunks * 100).toInt() : 0;
    final cachedMbStr = vm.cachedMb.toStringAsFixed(1);
    final totalMbStr = vm.totalMb.toStringAsFixed(1);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.80,
        ),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.cloud_sync_rounded, color: colors.accentPrimary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Streaming & Cache Inspector',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (file != null)
                          Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.textSecondary, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colors.textSecondary, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: colors.borderSubtle, height: 1),

            // Summary Card
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.bgPrimary.withValues(alpha: 0.60),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.borderSubtle.withValues(alpha: 0.50)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cached Chunks',
                          style: TextStyle(color: colors.textSecondary, fontSize: 13),
                        ),
                        Text(
                          '$cachedCount of $totalChunks ($percent%)',
                          style: TextStyle(
                            color: colors.accentPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: totalChunks > 0 ? (cachedCount / totalChunks) : 0.0,
                        backgroundColor: colors.borderSubtle.withValues(alpha: 0.30),
                        valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Downloaded Data',
                          style: TextStyle(color: colors.textSecondary, fontSize: 12),
                        ),
                        Text(
                          '$cachedMbStr / $totalMbStr MB',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Chunk List Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Chunks ($totalChunks total)',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      _buildLegendDot(colors.accentPrimary, 'Cached', colors),
                      const SizedBox(width: 12),
                      _buildLegendDot(colors.fileVideo, 'Downloading', colors),
                      const SizedBox(width: 12),
                      _buildLegendDot(colors.borderSubtle, 'Queued', colors),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Chunk List
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                physics: const BouncingScrollPhysics(),
                itemCount: totalChunks,
                itemBuilder: (context, index) {
                  final isCached = cached.contains(index);
                  final isDownloading = inFlight.containsKey(index);
                  final downloadFraction = inFlight[index] ?? 0.0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isCached
                          ? colors.accentPrimary.withValues(alpha: 0.10)
                          : isDownloading
                              ? colors.fileVideo.withValues(alpha: 0.10)
                              : colors.bgPrimary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isCached
                            ? colors.accentPrimary.withValues(alpha: 0.40)
                            : isDownloading
                                ? colors.fileVideo.withValues(alpha: 0.50)
                                : colors.borderSubtle.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isCached
                              ? Icons.check_circle_rounded
                              : isDownloading
                                  ? Icons.downloading_rounded
                                  : Icons.schedule_rounded,
                          size: 18,
                          color: isCached
                              ? colors.accentPrimary
                              : isDownloading
                                  ? colors.fileVideo
                                  : colors.textTertiary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Chunk #${index + 1}',
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        if (isCached)
                          Text(
                            'Cached',
                            style: TextStyle(
                              color: colors.accentPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          )
                        else if (isDownloading)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 50,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: downloadFraction,
                                    backgroundColor: colors.borderSubtle.withValues(alpha: 0.30),
                                    valueColor: AlwaysStoppedAnimation<Color>(colors.fileVideo),
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(downloadFraction * 100).toInt()}%',
                                style: TextStyle(
                                  color: colors.fileVideo,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            'Queued',
                            style: TextStyle(color: colors.textTertiary, fontSize: 12),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label, AppColorsExtension colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: colors.textSecondary, fontSize: 11),
        ),
      ],
    );
  }
}
