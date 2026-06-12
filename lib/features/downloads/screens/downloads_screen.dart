import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/models/download_job.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/service_locator.dart';

/// Downloads screen — displays concurrent download jobs with active, queued, and completed sections.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      await ServiceLocator.instance.init();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ── File type helpers ─────────────────────────────────────────────────────

  static IconData _icon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_rounded;
    if (mimeType.startsWith('video/')) return Icons.video_file_rounded;
    if (mimeType.startsWith('audio/')) return Icons.audio_file_rounded;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_rounded;
    return Icons.insert_drive_file_rounded;
  }

  static Color _color(String mimeType) {
    if (mimeType.startsWith('image/')) return const Color(0xFF3B82F6);
    if (mimeType.startsWith('video/')) return const Color(0xFFA855F7);
    if (mimeType.startsWith('audio/')) return const Color(0xFFF59E0B);
    if (mimeType == 'application/pdf') return const Color(0xFFEF4444);
    return AppTheme.primary;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Safety check for unit tests/web design where locator might not be initialized yet
    final isReady = ServiceLocator.instance.isInitialized && !_isLoading;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: const Text('Downloads'),
        automaticallyImplyLeading: false,
        actions: isReady
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  tooltip: 'Clear Completed History',
                  onPressed: () {
                    ServiceLocator.instance.downloadQueue
                        .clearCompletedHistory();
                  },
                ),
              ]
            : null,
      ),
      body: !isReady
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppTheme.primary),
              ),
            )
          : ValueListenableBuilder<Box<DownloadJob>>(
              valueListenable: ServiceLocator.instance.downloadQueue.listenable,
              builder: (context, box, _) {
                final jobs = ServiceLocator.instance.downloadQueue.allJobs;
                if (jobs.isEmpty) {
                  return _buildEmptyState(context);
                }
                return _buildList(context, jobs);
              },
            ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Gradient circle icon
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withAlpha(30),
                    const Color(0xFFA78BFA).withAlpha(30),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                Icons.download_rounded,
                size: 44,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 20),

            // Gradient shader title
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppTheme.primary, Color(0xFFA78BFA)],
              ).createShader(bounds),
              child: Text(
                'No downloads yet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              'Downloaded files will appear here',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Scrollable list with sections ─────────────────────────────────────────

  Widget _buildList(BuildContext context, List<DownloadJob> jobs) {
    final active = jobs.where((j) => !j.isComplete).toList();
    final completed = jobs.where((j) => j.isComplete).toList();
    var animIndex = 0;

    return CustomScrollView(
      slivers: [
        // ── Active / Queued Downloads ──────────────────────────────────────
        if (active.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
                child: _sectionHeader('Queue / In Progress')),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: active.length,
              itemBuilder: (context, index) {
                final idx = animIndex++;
                final tile = _ActiveDownloadTile(
                  download: active[index],
                  iconData: _icon(active[index].mimeType),
                  iconColor: _color(active[index].mimeType),
                  onCancel: () {
                    ServiceLocator.instance.downloadQueue
                        .cancelDownload(active[index].fileId);
                  },
                  onRetry: () {
                    final fileRecord = ServiceLocator.instance.hive
                        .getFile(active[index].fileId);
                    if (fileRecord != null) {
                      ServiceLocator.instance.downloadQueue
                          .enqueueDownload(fileRecord);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('File metadata not found, cannot retry')),
                      );
                    }
                  },
                  onDelete: () {
                    ServiceLocator.instance.downloadQueue
                        .removeJob(active[index].fileId);
                  },
                );
                return tile
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (idx * 40).ms)
                    .slideX(begin: 0.03, end: 0);
              },
            ),
          ),
        ],

        // ── Completed Downloads ───────────────────────────────────────────
        if (completed.isNotEmpty) ...[
          SliverPadding(
            padding:
                EdgeInsets.fromLTRB(16, active.isNotEmpty ? 20 : 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _sectionHeader('Completed')),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: completed.length,
              itemBuilder: (context, index) {
                final idx = animIndex++;
                final tile = _CompletedDownloadTile(
                  download: completed[index],
                  iconData: _icon(completed[index].mimeType),
                  iconColor: _color(completed[index].mimeType),
                  onOpen: () {
                    final path = completed[index].localPath;
                    if (path != null) {
                      OpenFile.open(path);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Saved path not found locally')),
                      );
                    }
                  },
                  onShare: () {
                    final path = completed[index].localPath;
                    if (path != null) {
                      SharePlus.instance.share(
                        ShareParams(
                          files: [XFile(path)],
                          text: completed[index].name,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Saved path not found locally')),
                      );
                    }
                  },
                  onDelete: () {
                    ServiceLocator.instance.downloadQueue
                        .removeJob(completed[index].fileId);
                  },
                );
                return tile
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (idx * 40).ms)
                    .slideX(begin: 0.03, end: 0);
              },
            ),
          ),
        ],

        // Bottom padding so content doesn't sit behind nav bar
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4, left: 2),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.primary,
            letterSpacing: 1.1,
          ),
        ),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── Active download tile ────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

class _ActiveDownloadTile extends StatelessWidget {
  final DownloadJob download;
  final IconData iconData;
  final Color iconColor;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const _ActiveDownloadTile({
    required this.download,
    required this.iconData,
    required this.iconColor,
    required this.onCancel,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isQueued = download.isQueued;
    final isFailed = download.isFailed;
    final isCancelled = download.isCancelled;

    String statusText = '';
    if (isQueued) {
      statusText = 'Queued';
    } else if (isFailed) {
      statusText = 'Failed';
    } else if (isCancelled) {
      statusText = 'Cancelled';
    } else {
      final pct = (download.progress * 100).toStringAsFixed(0);
      statusText = '$pct%';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // File type icon box
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(iconData, color: iconColor, size: 22),
                ),
                const SizedBox(width: 12),

                // Filename and size
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        download.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isFailed && download.error != null
                            ? download.error!
                            : '${download.sizeMb.toStringAsFixed(1)} MB',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isFailed ? AppTheme.error : null,
                            ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),

                // Percentage label
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: isFailed
                          ? AppTheme.error
                          : (isCancelled ? Colors.grey : AppTheme.primary),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

                // Action buttons
                if (isFailed || isCancelled) ...[
                  // Retry button
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.refresh_rounded,
                          size: 20, color: AppTheme.primary),
                      tooltip: 'Retry download',
                      onPressed: onRetry,
                    ),
                  ),
                  // Delete button
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      tooltip: 'Remove from history',
                      onPressed: onDelete,
                    ),
                  ),
                ] else ...[
                  // Cancel button
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      tooltip: 'Cancel download',
                      onPressed: onCancel,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // ── Progress bar ──────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: isQueued
                    ? null
                    : (isFailed || isCancelled ? 0.0 : download.progress),
                minHeight: 5,
                backgroundColor: isDark
                    ? Colors.white.withAlpha(15)
                    : Colors.black.withAlpha(15),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isFailed
                      ? AppTheme.error
                      : (isCancelled ? Colors.grey : AppTheme.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── Completed download tile ─────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

class _CompletedDownloadTile extends StatelessWidget {
  final DownloadJob download;
  final IconData iconData;
  final Color iconColor;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  const _CompletedDownloadTile({
    required this.download,
    required this.iconData,
    required this.iconColor,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // File type icon box
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(iconData, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),

            // Filename, size · date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    download.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${download.sizeMb.toStringAsFixed(1)} MB · ${_formatDate(download.completedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),

            // Action buttons
            _SmallActionButton(
              icon: Icons.open_in_new_rounded,
              label: 'Open',
              onTap: onOpen,
            ),
            const SizedBox(width: 6),
            _SmallActionButton(
              icon: Icons.share_rounded,
              label: 'Share',
              onTap: onShare,
            ),
            const SizedBox(width: 4),
            // Delete button (history only)
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                tooltip: 'Remove from history',
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── Small action button (Open / Share) ──────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

class _SmallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SmallActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: AppTheme.primary.withAlpha(isDark ? 25 : 18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppTheme.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
