/*
 * File: downloads_screen.dart
 * Description: Transfers screen displaying active downloads, uploads, and shared links using centralized shared widgets.
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../../../core/models/download_job.dart';
import '../../../../../../core/models/file_record.dart';
import '../../../../../../core/models/transfer_task.dart';
import '../../../../../../core/navigation/navigation_intent.dart';
import '../../../../../../core/services/service_locator.dart';
import '../../../../../../core/theme/app_theme.dart';
import '../../../../../../core/utils/file_opener_helper.dart';
import '../../../../../../shared/widgets/dialogs/app_dialogs.dart';
import '../../../../../../shared/widgets/feedback/app_empty_state.dart';
import '../../../../../../shared/widgets/share_link_sheet.dart';
import '../../../../../../shared/widgets/tiles/app_file_tile.dart';
import '../../../../../../shared/widgets/typography/app_section_label.dart';
import 'viewmodel/downloads_view_model.dart';
import 'widgets/downloads_active_section.dart';
import 'widgets/downloads_completed_section.dart';
import 'widgets/downloads_header.dart';
import 'widgets/downloads_shared_section.dart';

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
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
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
  void _openFile(String? localPath, {String? mimeType, String? fileName}) {
    if (localPath != null && localPath.isNotEmpty) {
      FileOpenerHelper.openFile(
        context,
        filePath: localPath,
        mimeType: mimeType,
        fileName: fileName,
      );
    }
  }

  /// Copies share URL to clipboard.
  Future<void> _copyUrl(String url) async {
    HapticFeedback.lightImpact();
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share link copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Shares link or file externally using system share sheet.
  void _shareUrl(String url) {
    HapticFeedback.lightImpact();
    SharePlus.instance.share(ShareParams(text: url));
  }

  /// Deletes and expires the share link remotely and locally.
  Future<void> _deleteShareLink(String fileId, String fileName) async {
    HapticFeedback.heavyImpact();
    final ok = await AppDialogs.showConfirm(
      context,
      title: 'Delete Share Link?',
      message:
          'Are you sure you want to expire and delete the share link for "$fileName"?',
      confirmText: 'Delete Link',
      isDestructive: true,
    );
    if (ok == true && mounted) {
      HapticFeedback.heavyImpact();
      await context.read<TransferCubit>().deleteShareJob(fileId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Share link deleted and expired.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Deletes downloaded file from device storage after confirmation.
  Future<void> _deleteDownloadedFile(DownloadJob job) async {
    HapticFeedback.heavyImpact();
    final ok = await AppDialogs.showConfirm(
      context,
      title: 'Delete Downloaded File?',
      message:
          'Are you sure you want to remove "${job.name}" from device storage?',
      confirmText: 'Delete',
      isDestructive: true,
    );
    if (ok == true && mounted) {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      context.read<TransferCubit>().deleteDownloadedFile(job.fileId);
    }
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
          context.read<TransferCubit>().enqueueShare(
                file,
                password: pwd,
                expiryDays: expiryDays,
                vanitySlug: vanitySlug,
              );
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: DownloadsHeader(
        activeTab: _activeTab,
        isSearching: _isSearching,
        searchCtrl: _searchCtrl,
        onTabChanged: (i) => setState(() => _activeTab = i),
        onToggleSearch: () {
          setState(() {
            _isSearching = !_isSearching;
            if (!_isSearching) _searchCtrl.clear();
          });
        },
        onSearchQueryChanged: (val) => setState(() {}),
        onClearCompleted: () async {
          final cubit = context.read<TransferCubit>();
          final ok = await AppDialogs.showConfirm(
            context,
            title: 'Clear Transfer History',
            message:
                'Are you sure you want to clear completed transfer records?',
            confirmText: 'Clear',
            isDestructive: true,
          );
          if (ok == true && mounted) {
            cubit.clearCompletedDownloads();
          }
        },
      ),
      body: BlocBuilder<TransferCubit, TransferState>(
        builder: (context, state) {
          final query = _searchCtrl.text.toLowerCase().trim();

          // Active transfers
          final activeTransfers = state.activeTasks.where((t) {
            if (!t.isActive) return false;
            if (_activeTab == 0 && t.type != TransferType.download) {
              return false;
            }
            if (_activeTab == 1 && t.type != TransferType.upload) {
              return false;
            }
            if (_activeTab == 2) return false;
            if (query.isNotEmpty && !t.name.toLowerCase().contains(query)) {
              return false;
            }
            return true;
          }).toList();

          // Completed downloads
          final completedDownloads = state.downloadJobs.where((j) {
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
            return AppEmptyState(
              icon: _activeTab == 0
                  ? Icons.cloud_download_outlined
                  : (_activeTab == 1
                      ? Icons.cloud_upload_outlined
                      : Icons.share_outlined),
              title: _activeTab == 0
                  ? 'No Downloads'
                  : (_activeTab == 1 ? 'No Uploads' : 'No Shared Links'),
              subtitle: _activeTab == 0
                  ? 'Downloaded files will appear here.'
                  : (_activeTab == 1
                      ? 'Uploaded files will appear here.'
                      : 'Files shared via web link will appear here.'),
            );
          }

          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              DownloadsActiveSection(activeTransfers: activeTransfers),
              if (_activeTab == 0 && completedDownloads.isNotEmpty)
                DownloadsCompletedSection(
                  completedDownloads: completedDownloads,
                  onOpenFile: _openFile,
                  onShareFile: _showShareSheet,
                  onDeleteJob: _deleteDownloadedFile,
                ),
              if (_activeTab == 1 && uploadFiles.isNotEmpty) ...[
                AppSectionLabel(
                  label: 'Uploaded Files (${uploadFiles.length})',
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                ),
                ...uploadFiles.map(
                  (file) => AppFileTile(
                    file: file,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _showShareSheet(file);
                    },
                    trailing: IconButton(
                      icon: Icon(Icons.share_outlined,
                          color: colors.textSecondary, size: 20),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _showShareSheet(file);
                      },
                    ),
                  ),
                ),
              ],
              if (_activeTab == 2 && sharedLinks.isNotEmpty)
                DownloadsSharedSection(
                  sharedLinks: sharedLinks,
                  onCopyUrl: _copyUrl,
                  onShareUrl: _shareUrl,
                  onDeleteShareLink: _deleteShareLink,
                ),
            ],
          );
        },
      ),
    );
  }
}
