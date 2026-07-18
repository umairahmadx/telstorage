import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/file_record.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/navigation/navigation_intent.dart';
import '../../../shared/widgets/thumbnail_widget.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../shared/widgets/file_detail_sheet.dart';
import '../../../shared/widgets/share_link_sheet.dart';
import '../bloc/home_cubit.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    context.read<HomeCubit>().initialize();
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
    final existing = context.read<HomeCubit>().getShareJob(file.fileId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: file,
        shareUrl: existing?.shareUrl,
        onCopyLink: (pwd, expiry) async {
          final cubit = context.read<HomeCubit>();
          await cubit.shareFile(file, password: pwd, expiryDays: expiry);

          if (!mounted || !ctx.mounted) return;
          Navigator.pop(ctx);

          final job = cubit.getShareJob(file.fileId);
          if (job != null && job.isComplete && job.shareUrl != null) {
            await Clipboard.setData(ClipboardData(text: job.shareUrl!));
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: const Text('Link copied to clipboard!'),
                  backgroundColor: Theme.of(context).extension<AppColorsExtension>()?.success ?? Colors.green),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: const Text('Sharing started. Check "Transfer" tab.'),
                  backgroundColor: Theme.of(context).extension<AppColorsExtension>()?.success ?? Colors.green),
            );
          }
        },
      ),
    );
  }

  Future<void> _downloadFile(FileRecord file) async {
    await context.read<HomeCubit>().downloadFile(file);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('"${file.name}" added to downloads'),
          backgroundColor: Theme.of(context).extension<AppColorsExtension>()?.success ?? Colors.green),
    );
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
                        value: state.syncProgress > 0 ? state.syncProgress : null,
                        color: colors.accentPrimary,
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.file_download_outlined),
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
                  _buildGreetingCard(colors, state),
                  const SizedBox(height: 24),
                  _buildStorageOverview(colors, state),
                  const SizedBox(height: 32),
                  _buildRecentFilesHeader(colors),
                  const SizedBox(height: 16),
                  _buildRecentFilesList(colors, state),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGreetingCard(AppColorsExtension colors, HomeState state) {
    final name = state.userName ?? 'User';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Good morning, $name',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(width: 8),
                    const Text('👋', style: TextStyle(fontSize: 20)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  state.isSyncing ? state.syncStatus : 'Your files are safe and synced.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.bgPrimary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildStorageOverview(AppColorsExtension colors, HomeState state) {
    final usedMb = state.storageUsedMb;
    final limitMb = state.metadata?.storageLimitMb ?? 102400; // fallback to 100GB
    final usedText = usedMb >= 1024
        ? '${(usedMb / 1024).toStringAsFixed(1)} GB'
        : '${usedMb.toStringAsFixed(0)} MB';

    final totalFiles = state.totalFiles;
    final totalShares = state.totalShares;
    final totalDownloads = state.totalDownloads;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Storage Overview',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                TextSpan(
                  text: usedText,
                  style: TextStyle(
                      color: colors.textPrimary, fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' of Unlimited used'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (usedMb / limitMb).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: colors.bgSurfaceInset,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accentPrimary),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem(colors, Icons.cloud_upload_outlined, 'Uploaded',
                  '$totalFiles Files'),
              _buildStatItem(
                  colors, Icons.share_outlined, 'Shared', '$totalShares Links'),
              _buildStatItem(colors, Icons.file_download_outlined, 'Downloads',
                  '$totalDownloads Files'),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, delay: 100.ms)
        .slideY(begin: 0.1, end: 0);
  }

  Widget _buildStatItem(
      AppColorsExtension colors, IconData icon, String label, String value) {
    return Container(
      width: 95,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: colors.bgSurfaceInset,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: colors.textPrimary, size: 20),
          const SizedBox(height: 8),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(color: colors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildRecentFilesHeader(AppColorsExtension colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Recent Files',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        GestureDetector(
          onTap: () => ServiceLocator.instance.navigation
              .navigateTo(AppDestination.files),
          child: Text(
            'View all',
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentFilesList(AppColorsExtension colors, HomeState state) {
    final files = state.recentFiles;

    if (files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Text('No recent files',
              style: TextStyle(color: colors.textTertiary)),
        ),
      );
    }

    return Column(
      children: files
          .map((f) => _RecentFileTile(
                file: f,
                onMore: () => _showFileDetail(f),
              ))
          .toList(),
    );
  }
}

class _RecentFileTile extends StatelessWidget {
  final FileRecord file;
  final VoidCallback onMore;
  const _RecentFileTile({required this.file, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildLeading(colors),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${file.formattedSize} • ${_formatDate(file.uploadedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.more_horiz_rounded, color: colors.textSecondary),
            onPressed: onMore,
          ),
        ],
      ),
    );
  }

  Widget _buildLeading(AppColorsExtension colors) {
    final mime = file.mimeType;
    if (mime.startsWith('image/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: ThumbnailWidget(
            file: file,
            width: 48,
            height: 48,
            fallback: Container(
              color: colors.bgSurfaceInset,
              child: Icon(Icons.image_rounded, color: colors.textPrimary.withAlpha(60)),
            ),
          ),
        ),
      );
    }

    Color iconColor;
    String label = '';

    if (mime.startsWith('video/')) {
      iconColor = colors.fileVideo;
      label = 'VIDEO';
    } else if (mime == 'application/pdf') {
      iconColor = colors.filePdf;
      label = 'PDF';
    } else if (file.name.endsWith('.fig')) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: colors.bgSurfaceInset,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child:
            Icon(Icons.palette_outlined, color: colors.filePalette, size: 24),
      );
    } else {
      iconColor = colors.fileZip;
      label = 'ZIP';
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: iconColor.withAlpha(40),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
            color: iconColor, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
