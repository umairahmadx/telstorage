import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';

import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/download_job.dart';
import '../../../core/models/web_share_job.dart';
import '../../../core/models/file_record.dart';
import '../../../shared/widgets/thumbnail_widget.dart';
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

  Future<void> _confirmAndDeleteJob(String fileId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Download?'),
        content: Text(
          'Permanently delete "$name"? The downloaded file will be removed from your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ServiceLocator.instance.downloadQueue.deleteJobAndLocalFile(fileId);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Safety check for unit tests/web design where locator might not be initialized yet
    final isReady = ServiceLocator.instance.isInitialized && !_isLoading;

    if (!isReady) {
      return Scaffold(
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        appBar: AppBar(
          title: const Text('Downloads & Shares'),
          automaticallyImplyLeading: false,
        ),
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppTheme.primary),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        appBar: AppBar(
          title: const Text('Downloads & Shares'),
          automaticallyImplyLeading: false,
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.download_rounded), text: 'Downloads'),
              Tab(icon: Icon(Icons.public_rounded), text: 'Web Shares'),
            ],
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.primary,
          ),
          actions: [
            Builder(
              builder: (context) {
                final tabController = DefaultTabController.of(context);
                return AnimatedBuilder(
                  animation: tabController,
                  builder: (context, _) {
                    if (tabController.index == 0) {
                      return IconButton(
                        icon: const Icon(Icons.delete_sweep_rounded),
                        tooltip: 'Clear Completed Downloads',
                        onPressed: () {
                          ServiceLocator.instance.downloadQueue
                              .clearCompletedHistory();
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                );
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // Tab 1: Downloads
            ValueListenableBuilder<Box<DownloadJob>>(
              valueListenable: ServiceLocator.instance.downloadQueue.listenable,
              builder: (context, box, _) {
                final jobs = ServiceLocator.instance.downloadQueue.allJobs;
                if (jobs.isEmpty) {
                  return _buildEmptyState(context);
                }
                return _buildList(context, jobs);
              },
            ),
            // Tab 2: Web Shares
            ValueListenableBuilder<Box>(
              valueListenable: ServiceLocator.instance.webShareQueue.listenable,
              builder: (context, box, _) {
                final shares = ServiceLocator.instance.webShareQueue.allShares;
                if (shares.isEmpty) {
                  return _buildWebSharesEmptyState(context);
                }
                return _buildWebSharesList(context, shares);
              },
            ),
          ],
        ),
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
                  onDelete: () => _confirmAndDeleteJob(
                    active[index].fileId,
                    active[index].name,
                  ),
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
                  onDelete: () => _confirmAndDeleteJob(
                    completed[index].fileId,
                    completed[index].name,
                  ),
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

  Widget _buildWebSharesEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
                Icons.public_rounded,
                size: 44,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [AppTheme.primary, Color(0xFFA78BFA)],
              ).createShader(bounds),
              child: Text(
                'No web shares yet',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Long-press files in the browser and choose "Share Web Link"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebSharesList(BuildContext context, List<WebShareJob> shares) {
    final active = shares.where((s) => !s.isComplete && !s.isFailed).toList();
    final completed = shares.where((s) => s.isComplete || s.isFailed).toList();
    var animIndex = 0;

    return CustomScrollView(
      slivers: [
        if (active.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
                child: _sectionHeader('Uploading / Processing')),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: active.length,
              itemBuilder: (context, index) {
                final idx = animIndex++;
                final tile = _ActiveWebShareTile(
                  job: active[index],
                  iconData: _icon(active[index].mimeType),
                  iconColor: _color(active[index].mimeType),
                  onCancel: () => _confirmAndDeleteWebShare(context, active[index]),
                );
                return tile
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (idx * 40).ms)
                    .slideX(begin: 0.03, end: 0);
              },
            ),
          ),
        ],

        if (completed.isNotEmpty) ...[
          SliverPadding(
            padding:
                EdgeInsets.fromLTRB(16, active.isNotEmpty ? 20 : 12, 16, 0),
            sliver: SliverToBoxAdapter(child: _sectionHeader('Completed Shares')),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: completed.length,
              itemBuilder: (context, index) {
                final idx = animIndex++;
                final job = completed[index];
                final tile = _CompletedWebShareTile(
                  job: job,
                  iconData: _icon(job.mimeType),
                  iconColor: _color(job.mimeType),
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: job.shareUrl ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied to clipboard!')),
                    );
                  },
                  onShare: () {
                    SharePlus.instance.share(
                      ShareParams(
                        text: '${job.name}: ${job.shareUrl}',
                      ),
                    );
                  },
                  onDelete: () => _confirmAndDeleteWebShare(context, job),
                  onSettings: () => _showWebShareSettings(context, job),
                );
                return tile
                    .animate()
                    .fadeIn(duration: 300.ms, delay: (idx * 40).ms)
                    .slideX(begin: 0.03, end: 0);
              },
            ),
          ),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  Future<void> _showWebShareSettings(BuildContext context, WebShareJob job) async {
    final queue = ServiceLocator.instance.webShareQueue;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Web Share Settings',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                job.name,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  job.password != null ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: job.password != null ? AppTheme.primary : null,
                ),
                title: const Text('Password Protection', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  job.password != null ? 'Password: ${job.password}' : 'Make this link private',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    if (job.password != null) {
                      try {
                        await queue.removePassword(job.fileId);
                        setModalState(() {});
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Password removed successfully')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    } else {
                      final ctrl = TextEditingController();
                      final pwd = await showDialog<String>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: const Text('Set Password'),
                          content: TextField(
                            controller: ctrl,
                            obscureText: true,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              hintText: '4-100 characters',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(dCtx, ctrl.text),
                              child: const Text('Set'),
                            ),
                          ],
                        ),
                      );
                      if (pwd != null && pwd.isNotEmpty) {
                        try {
                          await queue.setPassword(job.fileId, pwd);
                          setModalState(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Password set successfully')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      }
                    }
                  },
                  child: Text(job.password != null ? 'Remove' : 'Set'),
                ),
              ),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.onetwothree_rounded,
                  color: job.maxDownloads != null ? AppTheme.primary : null,
                ),
                title: const Text('Download Cap', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  job.maxDownloads != null
                      ? 'Limit: ${job.maxDownloads} downloads'
                      : 'Remove link after N downloads',
                ),
                trailing: TextButton(
                  onPressed: () async {
                    if (job.maxDownloads != null) {
                      try {
                        await queue.setMaxDownloads(job.fileId, null);
                        setModalState(() {});
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Download cap removed')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    } else {
                      final ctrl = TextEditingController();
                      final limitStr = await showDialog<String>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: const Text('Set Download Cap'),
                          content: TextField(
                            controller: ctrl,
                            keyboardType: TextInputType.number,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Max Downloads',
                              hintText: '1 to 1000',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(dCtx, ctrl.text),
                              child: const Text('Set'),
                            ),
                          ],
                        ),
                      );
                      if (limitStr != null && limitStr.isNotEmpty) {
                        final limit = int.tryParse(limitStr);
                        if (limit != null && limit > 0) {
                          try {
                            await queue.setMaxDownloads(job.fileId, limit);
                            setModalState(() {});
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Download cap set successfully')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        }
                      }
                    }
                  },
                  child: Text(job.maxDownloads != null ? 'Remove' : 'Set'),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteWebShare(BuildContext context, WebShareJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Web Share?'),
        content: Text(
          'This will permanently delete the file "${job.name}" from storage.to and revoke the public link.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ServiceLocator.instance.webShareQueue.deleteShare(job.fileId);
    }
  }

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

// ═══════════════════════════════════════════════════════════════════════════════
// ── Active Web Share tile ───────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

class _ActiveWebShareTile extends StatelessWidget {
  final WebShareJob job;
  final IconData iconData;
  final Color iconColor;
  final VoidCallback onCancel;

  const _ActiveWebShareTile({
    required this.job,
    required this.iconData,
    required this.iconColor,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    String statusText = 'Pending…';
    if (job.status == 'downloading') {
      statusText = 'Downloading from Telegram (${(job.progress * 100).toStringAsFixed(0)}%)';
    } else if (job.status == 'uploading') {
      statusText = 'Uploading to Web (${(job.progress * 100).toStringAsFixed(0)}%)';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(iconData, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.name,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${job.sizeMb.toStringAsFixed(1)} MB · $statusText',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined, size: 20, color: Colors.grey),
                  onPressed: onCancel,
                  tooltip: 'Cancel share',
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: job.progress > 0 ? job.progress : null,
                minHeight: 4,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ── Completed Web Share tile ────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════

class _CompletedWebShareTile extends StatelessWidget {
  final WebShareJob job;
  final IconData iconData;
  final Color iconColor;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onSettings;

  const _CompletedWebShareTile({
    required this.job,
    required this.iconData,
    required this.iconColor,
    required this.onCopy,
    required this.onShare,
    required this.onDelete,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final fileBox = Hive.box<FileRecord>(AppConstants.filesBox);
    final originalFile = fileBox.get(job.fileId);
    
    final fallbackIcon = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: job.isFailed ? Colors.red.withAlpha(25) : iconColor.withAlpha(25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        job.isFailed ? Icons.error_outline_rounded : iconData,
        color: job.isFailed ? Colors.red : iconColor,
        size: 22,
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (originalFile != null && !job.isFailed)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: ThumbnailWidget(
                    file: originalFile,
                    width: 42,
                    height: 42,
                    fallback: fallbackIcon,
                  ),
                ),
              )
            else
              fallbackIcon,
            
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: job.isFailed ? Colors.red : null,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    job.isFailed
                        ? 'Failed: ${job.error ?? "Unknown error"}'
                        : '${job.sizeMb.toStringAsFixed(1)} MB · ${_formatDate(job.completedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            if (!job.isFailed) ...[
              _SmallActionButton(
                icon: Icons.copy_rounded,
                label: 'Copy',
                onTap: onCopy,
              ),
              const SizedBox(width: 6),
              _SmallActionButton(
                icon: Icons.share_rounded,
                label: 'Share',
                onTap: onShare,
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.settings_outlined,
                    size: 18,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  tooltip: 'Web share settings',
                  onPressed: onSettings,
                ),
              ),
            ],
            
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
                tooltip: job.isFailed ? 'Clear' : 'Revoke share',
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
