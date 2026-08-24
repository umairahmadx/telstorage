/// File: home_screen.dart
/// Description: Home dashboard view displaying storage statistics, greeting, and recent files.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../core/models/file_record.dart';
import '../../../../../core/navigation/navigation_intent.dart';
import '../../../../../core/services/service_locator.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../../shared/widgets/file_detail_sheet.dart';
import '../../../../../shared/widgets/mobile_shell.dart';
import '../../../../../shared/widgets/share_link_sheet.dart';
import 'viewmodel/home_view_model.dart';
import 'widgets/home_greeting_card.dart';
import 'widgets/recent_files_section.dart';
import 'widgets/storage_overview_card.dart';

/// Screen component rendering the main dashboard.
class HomeScreen extends StatefulWidget {
  /// Constructs the HomeScreen.
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// State controller for HomeScreen initializing dashboard data.
class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    context.read<HomeCubit>().initialize();
  }

  /// Displays file detail actions modal bottom sheet.
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

  /// Displays web share link configuration bottom sheet.
  void _showShareSheet(FileRecord file) {
    final existing = context.read<HomeCubit>().getShareJob(file.fileId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: file,
        shareUrl: existing?.shareUrl,
        onCopyLink: (pwd, expiry, vanitySlug) async {
          final cubit = context.read<HomeCubit>();
          await cubit.shareFile(file,
              password: pwd, expiryDays: expiry, vanitySlug: vanitySlug);

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

  /// Triggers file download through ViewModel.
  Future<void> _downloadFile(FileRecord file) async {
    await context.read<HomeCubit>().downloadFile(file);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return BlocBuilder<HomeCubit, HomeState>(
      builder: (context, state) {
        if (state.isLoading && state.userName == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => MobileShell.of(context)?.openDrawer(),
            ),
            title: const Text('Home'),
            actions: [
              if (state.isSyncing)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value:
                            state.syncProgress > 0 ? state.syncProgress : null,
                        color: colors.accentPrimary,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.download_rounded),
                onPressed: () => ServiceLocator.instance.navigation
                    .navigateTo(AppDestination.transferDownloads),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => context.read<HomeCubit>().sync(),
            color: colors.accentPrimary,
            backgroundColor: colors.bgSurface,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  HomeGreetingCard(state: state),
                  const SizedBox(height: 24),
                  StorageOverviewCard(state: state),
                  const SizedBox(height: 32),
                  RecentFilesSection(
                    files: state.recentFiles,
                    onMore: _showFileDetail,
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
