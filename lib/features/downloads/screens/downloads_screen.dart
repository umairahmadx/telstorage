import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
import '../../../shared/widgets/thumbnail_widget.dart';
import '../../../shared/widgets/file_detail_sheet.dart';
import '../../../shared/widgets/share_link_sheet.dart';
import '../../../core/services/transfer_queue_service.dart';
import '../../../core/models/transfer_task.dart';
import '../bloc/transfer_cubit.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  int _activeTab = 0; // 0: Downloads, 1: Uploads, 2: Shared
  bool _isSearching = false;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    context.read<TransferCubit>().initialize();
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
        if (_scrollController.hasClients) {
          _scrollController.animateTo(0,
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      }
      final tabIndex = intent.transferTabIndex;
      if (tabIndex != null && tabIndex != _activeTab) {
        setState(() => _activeTab = tabIndex);
      }
    } else {
      final lastTab = ServiceLocator.instance.navigation.lastTransferTab;
      if (lastTab != _activeTab) {
        setState(() => _activeTab = lastTab);
      }
    }
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
    final existing = context.read<TransferCubit>().getShareJob(file.fileId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: file,
        shareUrl: existing?.shareUrl,
        onCopyLink: (pwd, expiry) async {
          final cubit = context.read<TransferCubit>();
          await cubit.enqueueShare(file, password: pwd, expiryDays: expiry);

          if (!mounted || !ctx.mounted) return;
          Navigator.pop(ctx);

          final job = cubit.getShareJob(file.fileId);
          if (job != null && job.isComplete && job.shareUrl != null) {
            await Clipboard.setData(ClipboardData(text: job.shareUrl!));
            if (!mounted) return;
            final colors = Theme.of(context).extension<AppColorsExtension>()!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: const Text('Link copied to clipboard!'),
                  backgroundColor: colors.success),
            );
          } else {
            final colors = Theme.of(context).extension<AppColorsExtension>()!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      const Text('Sharing started. View progress in "Shared" tab.'),
                  backgroundColor: colors.success),
            );
            setState(() => _activeTab = 2); // Switch to Shared tab
          }
        },
      ),
    );
  }

  Future<void> _downloadFile(FileRecord file) async {
    await context.read<TransferCubit>().enqueueDownload(file);
    if (!mounted) return;
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('"${file.name}" added to downloads'),
          backgroundColor: colors.success),
    );
  }


  void _showShareOptionsDialog(DownloadJob job, FileRecord? file) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Share "${job.name}"',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 20),
              if (job.isComplete && job.localPath != null)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.accentPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.description_outlined, color: colors.accentPrimary),
                  ),
                  title: Text(
                    'Share as File',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Send local file to apps',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    // ignore: deprecated_member_use
                    await Share.shareXFiles(
                      [XFile(job.localPath!)],
                      text: job.name,
                    );
                  },
                ),
              const SizedBox(height: 8),
              if (file != null)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.accentPrimary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.link_rounded, color: colors.accentPrimary),
                  ),
                  title: Text(
                    'Share as Link',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Generate web share link',
                    style: TextStyle(color: colors.textSecondary, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showShareSheet(file);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteLocalFile(DownloadJob job) async {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete from Phone?',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will remove "${job.name}" from your phone storage. It remains safe in Telegram Cloud.',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete', style: TextStyle(color: colors.bgPrimary)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<TransferCubit>().deleteDownloadedFile(job.fileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return BlocBuilder<TransferCubit, TransferState>(
      builder: (context, state) {
        if (state.isLoading && !state.isInitialized) {
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
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                        hintText: 'Search...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: colors.textTertiary)),
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
              _buildActiveTransfers(state),
              _buildSearchBar(colors),
              _buildSegmentedControl(colors),
              Expanded(
                child: _buildTabContent(colors, state),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveTransfers(TransferState state) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final active = state.activeTasks.where((t) => t.isActive).toList();
    
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
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
          Divider(
              height: 24, indent: 20, endIndent: 20, color: colors.borderSubtle),
        ],
      ),
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
          style: TextStyle(color: colors.textPrimary, fontSize: 15),
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
                      color: isSelected ? colors.bgPrimary : colors.textSecondary,
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

  Widget _buildTabContent(AppColorsExtension colors, TransferState state) {
    switch (_activeTab) {
      case 0:
        return _buildDownloadsTab(colors, state);
      case 1:
        return _buildUploadsTab(colors, state);
      case 2:
        return _buildSharedTab(colors, state);
      default:
        return const SizedBox();
    }
  }

  // ── DOWNLOADS TAB ─────────────────────────────────────────────────────────

  Widget _buildDownloadsTab(AppColorsExtension colors, TransferState state) {
    final jobs = state.downloadJobs;
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        _sectionLabel(colors, 'Downloads'),
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
                final file = context.read<TransferCubit>().getFile(job.fileId);
                return _DownloadItemTile(
                  job: job,
                  isLast: i == jobs.length - 1,
                  onShare: () => _showShareOptionsDialog(job, file),
                  onDelete: () => _confirmDeleteLocalFile(job),
                );
              }),
            ),
          ),
      ],
    );
  }

  // ── UPLOADS TAB ───────────────────────────────────────────────────────────

  Widget _buildUploadsTab(AppColorsExtension colors, TransferState state) {
    final uploads = state.uploadJobs;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        _buildUploadZone(colors),
        const SizedBox(height: 24),
        _sectionLabel(colors, 'Recent Uploads'),
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

  Widget _buildSharedTab(AppColorsExtension colors, TransferState state) {
    final shares = state.shareJobs;
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      children: [
        _sectionLabel(colors, 'Shared Files'),
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
                  onCopy: share.shareUrl != null
                      ? () {
                          Clipboard.setData(
                              ClipboardData(text: share.shareUrl!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Link copied to clipboard!')),
                          );
                        }
                      : null,
                  onShare: () {
                    if (share.shareUrl != null) {
                      SharePlus.instance.share(
                        ShareParams(
                          text: '${share.name}: ${share.shareUrl}',
                        ),
                      );
                    } else {
                      final file = context
                          .read<TransferCubit>()
                          .getFile(share.fileId);
                      if (file != null) _showShareSheet(file);
                    }
                  },
                  onDelete: () async {
                    await context
                        .read<TransferCubit>()
                        .deleteShareJob(share.fileId);
                  },
                );
              }),
            ),
          ),
      ],
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Widget _sectionLabel(AppColorsExtension colors, String text) => Text(
        text,
        style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.bold, color: colors.textPrimary),
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
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  const _DownloadItemTile(
      {required this.job, this.isLast = false, this.onShare, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isComplete = job.isComplete;
    final statusText = isComplete
        ? 'Completed'
        : (job.isCancelled
            ? 'Paused'
            : '${(job.progress * 100).toInt()}% complete');

    final file = context.read<TransferCubit>().getFile(job.fileId);

    return GestureDetector(
      onTap: isComplete && job.localPath != null
          ? () => OpenFile.open(job.localPath)
          : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (file != null)
                      ThumbnailWidget(file: file, width: 40, height: 40)
                    else
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.bgSurfaceInset,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                            isComplete
                                ? Icons.insert_drive_file_outlined
                                : Icons.file_download_outlined,
                            color: colors.textPrimary,
                            size: 20),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            job.name,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isComplete ? colors.accentPrimary : colors.textPrimary,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${job.sizeMb.toStringAsFixed(1)} MB • $statusText',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    // Share icon
                    IconButton(
                      icon: Icon(Icons.ios_share_rounded,
                          color: colors.accentPrimary, size: 20),
                      tooltip: 'Share',
                      onPressed: onShare,
                    ),
                    // Delete icon
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded,
                          color: colors.error, size: 20),
                      tooltip: 'Delete from phone',
                      onPressed: onDelete,
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
    
    // Attempt to find the FileRecord to show a proper thumbnail
    final file = context.read<TransferCubit>().state.uploadJobs
        .where((f) => f.name == name).firstOrNull;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (file != null)
                    ThumbnailWidget(file: file, width: 40, height: 40)
                  else
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconColor.withAlpha(40),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.description_rounded,
                          color: iconColor, size: 20),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
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
  final VoidCallback? onCopy;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  const _SharedItemTile(
      {required this.share,
      this.isLast = false,
      this.onCopy,
      this.onShare,
      this.onDelete});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final file = context.read<TransferCubit>().getFile(share.fileId);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Thumbnail
              file != null
                  ? ThumbnailWidget(file: file, width: 40, height: 40)
                  : Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.bgSurfaceInset,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_getIcon(share.mimeType),
                          color: _getColor(colors, share.mimeType), size: 20),
                    ),
              const SizedBox(width: 12),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      share.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Shared • ${_formatDate(share.completedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              // Copy link icon
              if (share.isComplete && share.shareUrl != null)
                IconButton(
                  icon: Icon(Icons.copy_rounded,
                      size: 18, color: colors.accentPrimary),
                  tooltip: 'Copy link',
                  onPressed: onCopy,
                ),
              // Share link icon
              IconButton(
                icon: Icon(Icons.ios_share_rounded,
                    size: 18, color: colors.accentPrimary),
                tooltip: 'Share link',
                onPressed: onShare,
              ),
              // Delete icon
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 18, color: colors.error),
                tooltip: 'Delete link',
                onPressed: onDelete,
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
    if (mime.startsWith('image/')) return Icons.image_rounded;
    if (mime.startsWith('video/')) return Icons.play_circle_fill_rounded;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _getColor(AppColorsExtension colors, String mime) {
    if (mime == 'application/pdf') return colors.filePdf;
    if (mime.startsWith('video/')) return colors.fileVideo;
    return colors.textSecondary;
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
        border: Border.all(color: colors.borderSubtle),
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
                        ? Icons.download_rounded
                        : Icons.share_rounded),
                size: 16,
                color: colors.accentPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.name,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary),
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
                          isPaused ? colors.warning : colors.textSecondary),
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
          const SizedBox(height: 4),
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
              backgroundColor: colors.bgSurfaceInset,
              valueColor: AlwaysStoppedAnimation<Color>(
                  isPaused ? colors.warning : colors.accentPrimary),
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
              color: colors.bgSurfaceInset,
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
              color: colors.bgSurfaceInset,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.close_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
