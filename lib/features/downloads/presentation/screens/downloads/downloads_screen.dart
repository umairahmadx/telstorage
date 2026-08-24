/// File: downloads_screen.dart
/// Description: Transfers screen displaying active downloads, uploads, and shared links.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../core/models/file_record.dart';
import '../../../../../core/models/transfer_task.dart';
import '../../../../../core/navigation/navigation_intent.dart';
import '../../../../../core/services/service_locator.dart';
import '../../../../../core/services/transfer_queue_service.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/share_link_sheet.dart';
import 'viewmodel/downloads_view_model.dart';
import 'widgets/active_download_tile.dart';
import 'widgets/completed_download_tile.dart';
import 'widgets/downloads_empty_state.dart';
import 'widgets/downloads_header.dart';

/// Screen component rendering active and completed transfer operations.
class DownloadsScreen extends StatefulWidget {
  /// Constructs DownloadsScreen.
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

/// State controller for DownloadsScreen handling tabs and transfer queues.
class _DownloadsScreenState extends State<DownloadsScreen> {
  /// Active tab index (0: Downloads, 1: Uploads, 2: Shared).
  int _activeTab = 0;

  /// Whether search mode is active.
  bool _isSearching = false;

  /// Search query controller.
  final TextEditingController _searchCtrl = TextEditingController();

  /// Primary scroll controller.
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

  /// Synchronizes active tab with deep-linked NavigationIntent.
  void _applyIntent() {
    final intent = ServiceLocator.instance.navigation.intentNotifier.value;
    if (intent != null) {
      if (intent.destination == AppDestination.transferActive) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
      }
      final tabIndex = intent.transferTabIndex;
      if (tabIndex != null && tabIndex != _activeTab) {
        setState(() {
          _activeTab = tabIndex;
        });
      }
    }
  }

  /// Triggers local file opening via platform handler.
  void _openFile(String? localPath) {
    if (localPath != null && localPath.isNotEmpty) {
      OpenFile.open(localPath);
    }
  }

  /// Shares link or file externally using system share sheet.
  void _shareUrl(String url) {
    SharePlus.instance.share(ShareParams(text: url));
  }

  /// Displays share configuration modal for a downloaded file.
  void _showShareSheet(FileRecord file) {
    final existing = context.read<TransferCubit>().getShareJob(file.fileId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: file,
        shareUrl: existing?.shareUrl,
        onCopyLink: (pwd, expiryDays, vanitySlug) async {
          final cubit = context.read<TransferCubit>();
          await cubit.enqueueShare(file,
              password: pwd, expiryDays: expiryDays, vanitySlug: vanitySlug);

          if (!mounted || !ctx.mounted) return;
          Navigator.pop(ctx);

          final job = cubit.getShareJob(file.fileId);
          if (job != null && job.isComplete && job.shareUrl != null) {
            await Clipboard.setData(ClipboardData(text: job.shareUrl!));
            if (!mounted) return;
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Scaffold(
      appBar: DownloadsHeader(
        activeTab: _activeTab,
        isSearching: _isSearching,
        searchCtrl: _searchCtrl,
        onTabChanged: (index) => setState(() => _activeTab = index),
        onToggleSearch: () {
          setState(() {
            _isSearching = !_isSearching;
            if (!_isSearching) _searchCtrl.clear();
          });
        },
        onSearchQueryChanged: (_) => setState(() {}),
        onClearCompleted: () {
          final state = context.read<TransferCubit>().state;
          for (final job in state.downloadJobs) {
            if (job.isComplete) {
              context
                  .read<TransferCubit>()
                  .deleteDownloadedFile(job.fileId);
            }
          }
        },
      ),
      body: BlocBuilder<TransferCubit, TransferState>(
        builder: (context, state) {
          if (state.isLoading && !state.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          final query = _searchCtrl.text.toLowerCase();

          // Active transfers
          final activeTransfers = state.activeTasks.where((t) {
            if (_activeTab == 0 && t.type != TransferType.download) {
              return false;
            }
            if (_activeTab == 1 && t.type != TransferType.upload) {
              return false;
            }
            if (query.isNotEmpty && !t.name.toLowerCase().contains(query)) {
              return false;
            }
            return true;
          }).toList();

          // Completed downloads
          final completedDownloads = state.downloadJobs.where((j) {
            if (!j.isComplete) return false;
            if (query.isNotEmpty && !j.name.toLowerCase().contains(query)) {
              return false;
            }
            return true;
          }).toList();

          // Completed uploads
          final uploadFiles = state.uploadJobs.where((f) {
            if (query.isNotEmpty && !f.name.toLowerCase().contains(query)) {
              return false;
            }
            return true;
          }).toList();

          // Shared links
          final sharedLinks = state.shareJobs.where((s) {
            final f = context.read<TransferCubit>().getFile(s.fileId);
            final name = f?.name ?? 'Shared File';
            if (query.isNotEmpty && !name.toLowerCase().contains(query)) {
              return false;
            }
            return true;
          }).toList();

          final hasItems = activeTransfers.isNotEmpty ||
              (_activeTab == 0 && completedDownloads.isNotEmpty) ||
              (_activeTab == 1 && uploadFiles.isNotEmpty) ||
              (_activeTab == 2 && sharedLinks.isNotEmpty);

          if (!hasItems) {
            return DownloadsEmptyState(activeTab: _activeTab);
          }

          return ListView(
            controller: _scrollController,
            children: [
              if (activeTransfers.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'ACTIVE (${activeTransfers.length})',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...activeTransfers.map(
                  (task) => ActiveDownloadTile(
                    task: task,
                    onPause: () =>
                        TransferQueueService.instance.pauseTask(task.id),
                    onResume: () =>
                        TransferQueueService.instance.resumeTask(task.id),
                    onCancel: () =>
                        TransferQueueService.instance.cancelTask(task.id),
                  ),
                ),
                const Divider(),
              ],
              if (_activeTab == 0 && completedDownloads.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'COMPLETED DOWNLOADS (${completedDownloads.length})',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...completedDownloads.map(
                  (job) => CompletedDownloadTile(
                    job: job,
                    file:
                        context.read<TransferCubit>().getFile(job.fileId),
                    onTap: () => _openFile(job.localPath),
                    onShare: () {
                      final file = context
                          .read<TransferCubit>()
                          .getFile(job.fileId);
                      if (file != null) _showShareSheet(file);
                    },
                    onDelete: () => context
                        .read<TransferCubit>()
                        .deleteDownloadedFile(job.fileId),
                  ),
                ),
              ],
              if (_activeTab == 1 && uploadFiles.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'UPLOADED FILES (${uploadFiles.length})',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...uploadFiles.map(
                  (file) => ListTile(
                    leading: const Icon(Icons.cloud_done_rounded),
                    title: Text(file.name),
                    subtitle: Text(
                        '${file.formattedSize} • ${file.uploadedAt.toLocal().toString().split('.')[0]}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.share_outlined),
                      onPressed: () => _showShareSheet(file),
                    ),
                  ),
                ),
              ],
              if (_activeTab == 2 && sharedLinks.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'SHARED LINKS (${sharedLinks.length})',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...sharedLinks.map((share) {
                  final file =
                      context.read<TransferCubit>().getFile(share.fileId);
                  final name = file?.name ?? 'Shared File';
                  return ListTile(
                    leading: const Icon(Icons.link_rounded),
                    title: Text(name),
                    subtitle: Text(share.shareUrl ?? 'Generating...'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (share.shareUrl != null)
                          IconButton(
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: share.shareUrl!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Link copied to clipboard')),
                              );
                            },
                          ),
                        if (share.shareUrl != null)
                          IconButton(
                            icon: const Icon(Icons.share_outlined),
                            onPressed: () => _shareUrl(share.shareUrl!),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => context
                              .read<TransferCubit>()
                              .deleteShareJob(share.fileId),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}
