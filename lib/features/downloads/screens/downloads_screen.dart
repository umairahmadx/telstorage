import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/download_job.dart';
import '../../../core/models/web_share_job.dart';
import '../../../core/models/file_record.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/navigation/navigation_intent.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../shared/widgets/file_detail_sheet.dart';
import '../../../shared/widgets/share_link_sheet.dart';
import '../../../core/services/transfer_queue_service.dart';
import '../../../core/models/transfer_task.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  int _activeTab = 0; // 0: Downloads, 1: Uploads, 2: Shared
  bool _isLoading = true;
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initServices();
    _applyIntent();
    ServiceLocator.instance.navigation.intentNotifier.addListener(_applyIntent);
  }

  @override
  void dispose() {
    ServiceLocator.instance.navigation.intentNotifier
        .removeListener(_applyIntent);
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _applyIntent() {
    final intent = ServiceLocator.instance.navigation.intentNotifier.value;
    if (intent != null) {
      if (intent.destination == AppDestination.transferActive) {
        // Stay on current tab but ensure we are on Transfer screen
        // (shellIndex already handled by MobileShell)
        // If we want to show active transfers, we might scroll to top
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
      final tabIndex = intent.transferTabIndex;
      if (tabIndex != null && tabIndex != _activeTab) {
        setState(() => _activeTab = tabIndex);
        // We do NOT clear the intent here yet, or maybe we should
        // to signify it has been "consumed" by the screen.
      }
    } else {
      // If no intent, restore from service's remembered state (Priority 3)
      final lastTab = ServiceLocator.instance.navigation.lastTransferTab;
      if (lastTab != _activeTab) {
        setState(() => _activeTab = lastTab);
      }
    }
  }

  Future<void> _initServices() async {
    try {
      await ServiceLocator.instance.init();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  void _showFileDetail(FileRecord file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FileDetailSheet(
        file: file,
        onShare: () {
          Navigator.pop(ctx);
          _showShareSheet(file);
        },
        onDownload: () {
          Navigator.pop(ctx);
          _downloadFile(file);
        },
        onRename: () => Navigator.pop(ctx),
        onDelete: () => Navigator.pop(ctx),
      ),
    );
  }

  void _showShareSheet(FileRecord file) {
    final queue = ServiceLocator.instance.webShareQueue;
    final existing =
        queue.allShares.where((s) => s.fileId == file.fileId).firstOrNull;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: file,
        shareUrl: existing?.shareUrl,
        onCopyLink: (pwd, expiry) async {
          final queue = ServiceLocator.instance.webShareQueue;
          await queue.enqueueShare(file, password: pwd, expiryDays: expiry);

          if (!mounted || !ctx.mounted) return;
          Navigator.pop(ctx);

          final existing =
              queue.allShares.firstWhere((s) => s.fileId == file.fileId);
          if (existing.isComplete && existing.shareUrl != null) {
            await Clipboard.setData(ClipboardData(text: existing.shareUrl!));
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Link copied to clipboard!'),
                  backgroundColor: Colors.green),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('Sharing started. View progress in "Shared" tab.'),
                  backgroundColor: Colors.green),
            );
            setState(() => _activeTab = 2); // Switch to Shared tab
          }
        },
      ),
    );
  }

  Future<void> _downloadFile(FileRecord file) async {
    await ServiceLocator.instance.downloadQueue.enqueueDownload(file);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('"${file.name}" added to downloads'),
          backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    if (!ServiceLocator.instance.isInitialized || _isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => MobileShell.of(context)?.openDrawer(),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    hintText: 'Search...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.white38)),
              )
            : const Text('Transfer'),
        centerTitle: true,
        actions: [
          IconButton(
            icon:
                Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              if (_isSearching) _searchCtrl.clear();
              _isSearching = !_isSearching;
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildActiveTransfers(),
          _buildSearchBar(colors),
          _buildSegmentedControl(colors),
          Expanded(
            child: _buildTabContent(colors),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTransfers() {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return ValueListenableBuilder<List<TransferTask>>(
      valueListenable: ServiceLocator.instance.transferQueue.tasksNotifier,
      builder: (context, tasks, _) {
        final active = tasks.where((t) => t.isActive).toList();
        if (active.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Active Transfers (${active.length})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (active.length > 1)
                      Text(
                        'Overall ${(active.fold(0.0, (s, t) => s + t.progress) / active.length * 100).toInt()}%',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: active.length,
                  itemBuilder: (context, index) {
                    final task = active[index];
                    return _ActiveTransferCard(task: task);
                  },
                ),
              ),
              const Divider(
                  height: 24, indent: 20, endIndent: 20, color: Colors.white10),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar(AppColorsExtension colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: BorderRadius.circular(25),
        ),
        child: TextField(
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search shared files and links...',
            hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded,
                color: colors.textTertiary, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedControl(AppColorsExtension colors) {
    final tabs = ['Downloads', 'Uploads', 'Shared'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final isSelected = _activeTab == i;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _activeTab = i);
                  ServiceLocator.instance.navigation
                      .updateRememberedTransferTab(i);
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        isSelected ? colors.accentPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    tabs[i],
                    style: TextStyle(
                      color: isSelected ? Colors.black : colors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildTabContent(AppColorsExtension colors) {
    switch (_activeTab) {
      case 0:
        return _buildDownloadsTab(colors);
      case 1:
        return _buildUploadsTab(colors);
      case 2:
        return _buildSharedTab(colors);
      default:
        return const SizedBox();
    }
  }

  // ── DOWNLOADS TAB ─────────────────────────────────────────────────────────

  Widget _buildDownloadsTab(AppColorsExtension colors) {
    return ValueListenableBuilder<Box<DownloadJob>>(
      valueListenable: ServiceLocator.instance.downloadQueue.listenable,
      builder: (context, box, _) {
        final jobs = ServiceLocator.instance.downloadQueue.allJobs;
        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            _sectionLabel('Downloads'),
            const SizedBox(height: 12),
            if (jobs.isEmpty)
              _buildEmptyState(
                  'No downloads yet', Icons.download_rounded, colors)
            else
              Container(
                decoration: BoxDecoration(
                  color: colors.bgSurface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: List.generate(jobs.length, (i) {
                    final job = jobs[i];
                    return _DownloadItemTile(
                      job: job,
                      isLast: i == jobs.length - 1,
                      onMore: () {
                        final file =
                            ServiceLocator.instance.hive.getFile(job.fileId);
                        if (file != null) _showFileDetail(file);
                      },
                    );
                  }),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── UPLOADS TAB ───────────────────────────────────────────────────────────

  Widget _buildUploadsTab(AppColorsExtension colors) {
    final hive = ServiceLocator.instance.hive;
    final uploads =
        hive.allFiles; // All files in Hive are basically uploaded files

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        _buildUploadZone(colors),
        const SizedBox(height: 24),
        _sectionLabel('Recent Uploads'),
        const SizedBox(height: 12),
        if (uploads.isEmpty)
          _buildEmptyState(
              'No uploads yet', Icons.cloud_upload_outlined, colors)
        else
          Container(
            decoration: BoxDecoration(
              color: colors.bgSurface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: List.generate(uploads.length, (i) {
                final file = uploads[i];
                return _UploadItemTile(
                  name: file.name,
                  size: file.formattedSize,
                  progress: 1.0,
                  status: 'Completed',
                  iconColor: colors.fileVideo,
                  isLast: i == uploads.length - 1,
                  onMore: () => _showFileDetail(file),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildUploadZone(AppColorsExtension colors) {
    return GestureDetector(
      onTap: () => MobileShell.of(context)?.switchTab(2), // Trigger add menu
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.borderSubtle, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_upload_outlined,
                color: colors.textSecondary, size: 32),
            const SizedBox(height: 12),
            Text(
              'Drag and upload or browse files',
              style: TextStyle(color: colors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ── SHARED TAB ────────────────────────────────────────────────────────────

  Widget _buildSharedTab(AppColorsExtension colors) {
    return ValueListenableBuilder<Box>(
      valueListenable: ServiceLocator.instance.webShareQueue.listenable,
      builder: (context, box, _) {
        final shares = ServiceLocator.instance.webShareQueue.allShares;
        return ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            _sectionLabel('Shared Files'),
            const SizedBox(height: 12),
            if (shares.isEmpty)
              _buildEmptyState(
                  'No web shares yet', Icons.public_rounded, colors)
            else
              Container(
                decoration: BoxDecoration(
                  color: colors.bgSurface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: List.generate(shares.length, (i) {
                    final share = shares[i];
                    return _SharedItemTile(
                      share: share,
                      isLast: i == shares.length - 1,
                      onMore: () {
                        final file =
                            ServiceLocator.instance.hive.getFile(share.fileId);
                        if (file != null) _showFileDetail(file);
                      },
                      onShare: () {
                        if (share.shareUrl != null) {
                          SharePlus.instance.share(
                            ShareParams(
                              text: '${share.name}: ${share.shareUrl}',
                            ),
                          );
                        } else {
                          final file = ServiceLocator.instance.hive
                              .getFile(share.fileId);
                          if (file != null) _showShareSheet(file);
                        }
                      },
                    );
                  }),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
      );

  Widget _buildEmptyState(
      String msg, IconData icon, AppColorsExtension colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 100),
      child: Column(
        children: [
          Center(child: Icon(icon, size: 48, color: colors.textTertiary)),
          const SizedBox(height: 16),
          Text(msg, style: TextStyle(color: colors.textTertiary)),
        ],
      ),
    );
  }
}

// ── TILE WIDGETS ─────────────────────────────────────────────────────────────

class _DownloadItemTile extends StatelessWidget {
  final DownloadJob job;
  final bool isLast;
  final VoidCallback? onMore;
  const _DownloadItemTile(
      {required this.job, this.isLast = false, this.onMore});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isComplete = job.isComplete;
    final statusText = isComplete
        ? 'Completed'
        : (job.isCancelled
            ? 'Paused'
            : '${(job.progress * 100).toInt()}% complete');

    return GestureDetector(
      onTap: isComplete && job.localPath != null
          ? () => OpenFile.open(job.localPath)
          : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.bgSurfaceInset,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                          isComplete
                              ? Icons.insert_drive_file_outlined
                              : Icons.file_download_outlined,
                          color: colors.textPrimary,
                          size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            job.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color:
                                      isComplete ? colors.accentPrimary : null,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${job.sizeMb.toStringAsFixed(1)} MB • $statusText',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.more_horiz_rounded,
                          color: colors.textSecondary),
                      onPressed: onMore,
                    ),
                  ],
                ),
                if (!isComplete) ...[
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: job.progress,
                      minHeight: 4,
                      backgroundColor: colors.bgSurfaceInset,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!isLast)
            Divider(indent: 16, endIndent: 16, color: colors.borderSubtle),
        ],
      ),
    );
  }
}

class _UploadItemTile extends StatelessWidget {
  final String name;
  final String size;
  final double progress;
  final String status;
  final Color iconColor;
  final bool isLast;
  final VoidCallback? onMore;

  const _UploadItemTile({
    required this.name,
    required this.size,
    required this.progress,
    required this.status,
    required this.iconColor,
    this.isLast = false,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isComplete = progress >= 1.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconColor.withAlpha(40),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.description_rounded,
                        color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$size • $status',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_horiz_rounded,
                        color: colors.textSecondary),
                    onPressed: onMore,
                  ),
                ],
              ),
              if (!isComplete) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: colors.bgSurfaceInset,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!isLast)
          Divider(indent: 16, endIndent: 16, color: colors.borderSubtle),
      ],
    );
  }
}

class _SharedItemTile extends StatelessWidget {
  final WebShareJob share;
  final bool isLast;
  final VoidCallback? onMore;
  final VoidCallback? onShare;
  const _SharedItemTile(
      {required this.share, this.isLast = false, this.onMore, this.onShare});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Column(
      children: [
        ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.bgSurfaceInset,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_getIcon(share.mimeType),
                color: _getColor(share.mimeType), size: 24),
          ),
          title:
              Text(share.name, style: Theme.of(context).textTheme.titleLarge),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shared by you • ${_formatDate(share.completedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (share.isComplete && share.shareUrl != null) ...[
                const SizedBox(height: 4),
                Text(
                  share.shareUrl!,
                  style: TextStyle(color: colors.accentPrimary, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (share.isComplete && share.shareUrl != null)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: share.shareUrl!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Link copied to clipboard!')),
                    );
                  },
                ),
              IconButton(
                icon: const Icon(Icons.share_outlined, size: 20),
                onPressed: onShare,
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz_rounded, size: 20),
                onPressed: onMore,
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(indent: 16, endIndent: 16, color: colors.borderSubtle),
      ],
    );
  }

  IconData _getIcon(String mime) {
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('video/')) return Icons.play_circle_outline;
    if (mime == 'application/pdf') return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  Color _getColor(String mime) {
    if (mime == 'application/pdf') return const Color(0xFFFF3B30);
    if (mime.startsWith('video/')) return const Color(0xFF5B7FFF);
    return Colors.white70;
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '';
    return DateFormat('dd MMM, yyyy').format(d);
  }
}

class _ActiveTransferCard extends StatelessWidget {
  final TransferTask task;

  const _ActiveTransferCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final speedText = task.speedKbps > 1024
        ? '${(task.speedKbps / 1024).toStringAsFixed(1)} MB/s'
        : '${task.speedKbps.toStringAsFixed(0)} KB/s';

    final isPaused = task.status == TransferStatus.paused;

    return Container(
      width: 280,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                task.type == TransferType.upload
                    ? Icons.cloud_upload_outlined
                    : (task.type == TransferType.download
                        ? Icons.file_download_outlined
                        : Icons.share_outlined),
                size: 16,
                color: colors.accentPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.name,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              _buildActionButtons(colors),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  task.currentStage ?? 'Processing...',
                  style: TextStyle(
                      fontSize: 11,
                      color:
                          isPaused ? AppTheme.warning : colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${(task.progress * 100).toInt()}%',
                style: TextStyle(
                    fontSize: 12,
                    color: colors.accentPrimary,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isPaused ? 'Paused' : speedText,
                style: TextStyle(fontSize: 10, color: colors.textTertiary),
              ),
              if (task.eta != null && !isPaused)
                Text(
                  '${task.eta} left',
                  style: TextStyle(fontSize: 10, color: colors.textTertiary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: task.progress,
              minHeight: 3,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                  isPaused ? AppTheme.warning : colors.accentPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(AppColorsExtension colors) {
    final isPaused = task.status == TransferStatus.paused;
    final queue = TransferQueueService.instance;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () =>
              isPaused ? queue.resumeTask(task.id) : queue.pauseTask(task.id),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 14,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => queue.cancelTask(task.id),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: Colors.white60,
            ),
          ),
        ),
      ],
    );
  }
}
