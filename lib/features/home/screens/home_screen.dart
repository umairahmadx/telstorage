import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/app_metadata.dart';
import '../../../core/models/file_record.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/navigation/navigation_intent.dart';
import '../../../shared/widgets/thumbnail_widget.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../shared/widgets/file_detail_sheet.dart';
import '../../../shared/widgets/share_link_sheet.dart';
import '../../storage/bloc/sync_cubit.dart';
import '../../../core/services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SyncCubit _syncCubit;
  AppMetadata? _meta;
  String _userName = 'User';

  @override
  void initState() {
    super.initState();
    _syncCubit = SyncCubit();
    _initAndSync();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _syncCubit.close();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final email = await AuthService.instance.getEmail();
    if (mounted && email != null) {
      setState(() {
        _userName = email.split('@').first;
        if (_userName.isNotEmpty) {
          _userName = _userName[0].toUpperCase() + _userName.substring(1);
        }
      });
    }
  }

  Future<void> _initAndSync() async {
    try {
      // ServiceLocator is already initialized in AuthBloc or SplashScreen
      // But we can call sync here as intended.
      _syncCubit.sync().then((_) => _loadMeta());
    } catch (_) {}
  }

  Future<void> _loadMeta() async {
    try {
      final m = await ServiceLocator.instance.metadata.fetch();
      if (mounted) setState(() => _meta = m);
    } catch (_) {}
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
        onRename: () {
          Navigator.pop(ctx);
        },
        onDelete: () {
          Navigator.pop(ctx);
        },
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
        onCopyLink: (pwd, expiry) {
          if (!mounted) return;
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Link copied with $expiry validity'),
                backgroundColor: Colors.green),
          );
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

    return BlocProvider.value(
      value: _syncCubit,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => MobileShell.of(context)?.openDrawer(),
          ),
          title: const Text('Home'),
          actions: [
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => ServiceLocator.instance.navigation
                  .navigateTo(AppDestination.transferDownloads),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _loadMeta,
          color: colors.accentPrimary,
          backgroundColor: colors.bgSurface,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                _buildGreetingCard(colors),
                const SizedBox(height: 24),
                _buildStorageOverview(colors),
                const SizedBox(height: 32),
                _buildRecentFilesHeader(colors),
                const SizedBox(height: 16),
                _buildRecentFilesList(colors),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGreetingCard(AppColorsExtension colors) {
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
                      'Good morning, $_userName',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(width: 8),
                    const Text('👋', style: TextStyle(fontSize: 20)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Your files are safe and synced.',
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
              _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
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

  Widget _buildStorageOverview(AppColorsExtension colors) {
    final usedMb = _meta?.storageUsedMb ?? 0;
    final limitMb = _meta?.storageLimitMb ?? 102400; // fallback to 100GB
    final usedText = usedMb >= 1024
        ? '${(usedMb / 1024).toStringAsFixed(1)} GB'
        : '${usedMb.toStringAsFixed(0)} MB';

    final hive = ServiceLocator.instance.hive;
    final totalFiles = hive.totalFiles;
    final totalShares = ServiceLocator.instance.webShareQueue.allShares.length;
    final totalDownloads = ServiceLocator.instance.downloadQueue.allJobs
        .where((j) => j.isComplete)
        .length;

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

  Widget _buildRecentFilesList(AppColorsExtension colors) {
    if (!ServiceLocator.instance.isInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: CircularProgressIndicator(color: colors.accentPrimary),
        ),
      );
    }

    return ValueListenableBuilder(
      valueListenable: ServiceLocator.instance.hive.filesListenable,
      builder: (context, _, __) {
        final files = ServiceLocator.instance.hive.recentFiles(5);

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
      },
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
              child: const Icon(Icons.image_rounded, color: Colors.white24),
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
          color: const Color(0xFF0D0D1D),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child:
            const Icon(Icons.palette_outlined, color: Colors.purple, size: 24),
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
