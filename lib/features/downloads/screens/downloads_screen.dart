import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/download_job.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/transfer_task.dart';
import '../../../core/navigation/navigation_intent.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/services/transfer_queue_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/share_link_sheet.dart';
import '../bloc/transfer_cubit.dart';
import 'widgets/active_download_tile.dart';
import 'widgets/completed_download_tile.dart';
import 'widgets/downloads_empty_state.dart';
import 'widgets/downloads_header.dart';

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

  void _showShareSheet(FileRecord file) {
    final existing = context.read<TransferCubit>().getShareJob(file.fileId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: file,
        shareUrl: existing?.shareUrl,
        onCopyLink: (pwd, expiry, vanitySlug) async {
          final cubit = context.read<TransferCubit>();
          await cubit.enqueueShare(file, password: pwd, expiryDays: expiry, vanitySlug: vanitySlug);

          if (!mounted || !ctx.mounted) return;
          Navigator.pop(ctx);

          final job = cubit.getShareJob(file.fileId);
          if (job != null && job.isComplete && job.shareUrl != null) {
            await Clipboard.setData(ClipboardData(text: job.shareUrl!));
            if (!mounted) return;
          } else {
            setState(() => _activeTab = 2);
          }
        },
      ),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: colors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      context.read<TransferCubit>().deleteDownloadedFile(job.fileId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: DownloadsHeader(
        activeTab: _activeTab,
        isSearching: _isSearching,
        searchCtrl: _searchCtrl,
        onTabChanged: (val) {
          setState(() => _activeTab = val);
          ServiceLocator.instance.navigation.updateRememberedTransferTab(val);
        },
        onToggleSearch: () {
          setState(() {
            _isSearching = !_isSearching;
            if (!_isSearching) {
              _searchCtrl.clear();
            }
          });
        },
        onSearchQueryChanged: (query) {},
        onClearCompleted: () {},
      ),
      body: BlocBuilder<TransferCubit, TransferState>(
        builder: (context, state) {
          if (state.isLoading && !state.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          final activeTasks = _activeTab == 0
              ? state.activeTasks
                  .where((t) => t.type == TransferType.download)
                  .toList()
              : (_activeTab == 1
                  ? state.activeTasks
                      .where((t) => t.type == TransferType.upload)
                      .toList()
                  : <TransferTask>[]);

          final completedJobs =
              state.downloadJobs.where((j) => j.isComplete).toList();
          final webShares = state.shareJobs;

          final isEmpty = (_activeTab == 0 && activeTasks.isEmpty && completedJobs.isEmpty) ||
              (_activeTab == 1 && activeTasks.isEmpty) ||
              (_activeTab == 2 && webShares.isEmpty);

          if (isEmpty) {
            return DownloadsEmptyState(activeTab: _activeTab);
          }

          return SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (activeTasks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      'ACTIVE TRANSFERS (${activeTasks.length})',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: activeTasks.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: colors.borderSubtle),
                    itemBuilder: (context, index) {
                      final task = activeTasks[index];
                      return ActiveDownloadTile(
                        task: task,
                        onPause: () => TransferQueueService.instance.pauseTask(task.id),
                        onResume: () => TransferQueueService.instance.resumeTask(task.id),
                        onCancel: () => TransferQueueService.instance.cancelTask(task.id),
                      );
                    },
                  ),
                  Divider(height: 24, thickness: 8, color: colors.bgSurfaceInset),
                ],
                if (_activeTab == 0 && completedJobs.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      'COMPLETED DOWNLOADS (${completedJobs.length})',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: completedJobs.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: colors.borderSubtle),
                    itemBuilder: (context, index) {
                      final job = completedJobs[index];
                      final file = context.read<TransferCubit>().getFile(job.fileId);
                      return CompletedDownloadTile(
                        job: job,
                        file: file,
                        onTap: () {
                          if (job.localPath != null) {
                            OpenFile.open(job.localPath!);
                          }
                        },
                        onShare: () => _showShareOptionsDialog(job, file),
                        onDelete: () => _confirmDeleteLocalFile(job),
                      );
                    },
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
