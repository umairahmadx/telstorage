import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/app_metadata.dart';
import '../../../core/models/file_record.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/responsive.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../shared/widgets/storage_ring.dart';
import '../../storage/bloc/sync_cubit.dart';
import '../../upload/bloc/upload_cubit.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SyncCubit _syncCubit;
  late final UploadCubit _uploadCubit;
  AppMetadata? _meta;

  @override
  void initState() {
    super.initState();
    _syncCubit = SyncCubit();
    _uploadCubit = UploadCubit();
    _initAndSync();
  }

  @override
  void dispose() {
    _syncCubit.close();
    _uploadCubit.close();
    super.dispose();
  }

  Future<void> _initAndSync() async {
    try {
      await ServiceLocator.instance.init();
      _syncCubit.sync().then((_) => _loadMeta());
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('credentials')) {
        Navigator.of(context).pushReplacementNamed(AppRouter.login);
      } else {
        _snack('Error initializing: $e');
      }
    }
  }

  Future<void> _loadMeta() async {
    try {
      final m = await ServiceLocator.instance.metadata.fetch();
      if (mounted) setState(() => _meta = m);
    } catch (e) {
      if (!mounted) return;
      _snack('Could not load storage info: $e');
    }
  }

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) { _snack('Could not read file'); return; }

    _uploadCubit.upload(bytes: file.bytes!, name: file.name, folderId: null);
  }

  void _snack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppTheme.success : AppTheme.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }


  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _syncCubit),
        BlocProvider.value(value: _uploadCubit),
      ],
      child: BlocConsumer<UploadCubit, UploadState>(
        listener: (ctx, state) {
          if (state is UploadSuccess) {
            _snack('${state.fileName} uploaded!', success: true);
            _loadMeta();
            _uploadCubit.reset();
          } else if (state is UploadError) {
            _snack('Upload failed: ${state.message}');
            _uploadCubit.reset();
          }
        },
        builder: (ctx, uploadState) {
          return BlocBuilder<SyncCubit, SyncState>(
            builder: (ctx, syncState) {
              final isUploading = uploadState is UploadInProgress;
              final content = _buildContent(uploadState);
              if (isMobile) {
                return Scaffold(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  appBar: _mobileAppBar(isUploading),
                  body: content,
                  floatingActionButton: _buildFab(isUploading),
                );
              }
              return AppShell(
                selectedIndex: 0,
                child: Scaffold(
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  appBar: _desktopTopBar(isUploading),
                  body: content,
                  floatingActionButton: _buildFab(isUploading),
                ),
              );
            },
          );
        },
      ),
    );
  }


  PreferredSizeWidget _mobileAppBar(bool isUploading) => PreferredSize(
    preferredSize: const Size.fromHeight(64),
    child: Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF2A2A45) : const Color(0xFFE0DFFF))),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: BlocBuilder<SyncCubit, SyncState>(
            builder: (ctx, syncState) {
              final isSyncing = syncState is SyncInProgress;
              final statusText = syncState is SyncInProgress ? syncState.status : 'Your cloud drive';
              return Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.primary, Color(0xFFA78BFA)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('TelStorage',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(statusText,
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ]),
                ),
                if (isSyncing)
                  const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
                else
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, size: 22),
                    tooltip: 'Sync',
                    onPressed: () => _syncCubit.sync().then((_) => _loadMeta()),
                  ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 22),
                  onPressed: () {
                    final shell = MobileShell.of(context);
                    if (shell != null) {
                      shell.switchTab(3); // Settings tab
                    } else {
                      Navigator.of(context).pushNamed(AppRouter.settings);
                    }
                  },
                ),
              ]);
            },
          ),
        ),
      ),
    ),
  );

  AppBar _desktopTopBar(bool isUploading) => AppBar(
    automaticallyImplyLeading: false,
    title: Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall),
    actions: [
      BlocBuilder<SyncCubit, SyncState>(
        builder: (ctx, syncState) {
          if (syncState is SyncInProgress) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(children: [
                const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
                const SizedBox(width: 8),
                Text(syncState.status,
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            );
          }
          return TextButton.icon(
            onPressed: () => _syncCubit.sync().then((_) => _loadMeta()),
            icon: const Icon(Icons.sync_rounded, size: 18),
            label: const Text('Sync'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
          );
        },
      ),
      const SizedBox(width: 8),
    ],
  );


  Widget _buildLoading() {
    final syncState = _syncCubit.state;
    final statusText = syncState is SyncInProgress ? syncState.status : 'Loading…';
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const SizedBox(
          width: 44, height: 44,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
          ),
        ),
        const SizedBox(height: 20),
        Text(statusText,
            style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }

  Widget _buildContent(UploadState uploadState) {
    final isSyncing = _syncCubit.state is SyncInProgress;
    final isLoading = isSyncing && _meta == null;
    if (isLoading) return _buildLoading();
    final isDesktop = Responsive.isDesktop(context);
    return isDesktop
        ? _buildDesktopLayout(uploadState)
        : _buildMobileLayout(uploadState);
  }

  // ── DESKTOP LAYOUT ────────────────────────────────────────────────────────
  Widget _buildDesktopLayout(UploadState uploadState) {
    final isUploading = uploadState is UploadInProgress;
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _loadMeta,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
        child: Column(children: [
          // Upload progress
          if (uploadState is UploadInProgress) _uploadProgressCard(uploadState),
          // Top row: storage ring + stats + quick upload
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Storage ring card
            SizedBox(
              width: 260,
              child: _glassCard(child: Column(children: [
                StorageRing(
                  usedMb: _meta?.storageUsedMb ?? 0,
                  limitMb: double.maxFinite,
                ),
                const SizedBox(height: 12),
                _statRow(),
              ])),
            ),
            const SizedBox(width: 20),
            // Quick Upload CTA
            Expanded(
              child: _glassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quick Upload',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text('Upload any file — videos, images, docs, and more.\nLarge files are automatically split into parts.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5)),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isUploading ? null : _pickAndUpload,
                        icon: const Icon(Icons.cloud_upload_rounded, size: 20),
                        label: const Text('Choose file to upload',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text('Max part size: 45 MB',
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          // Categories grid
          Text('Storage Categories', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          _categoryGrid(crossAxisCount: 4),
          const SizedBox(height: 28),
          // Recent files
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Recent Files', style: Theme.of(context).textTheme.titleLarge),
            TextButton(
              onPressed: () => Navigator.of(context)
                  .pushNamed(AppRouter.browser),
              child: Text('View All',
                  style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          _recentFilesCard(),
        ]),
      ),
    );
  }

  // ── MOBILE LAYOUT ─────────────────────────────────────────────────────────
  Widget _buildMobileLayout(UploadState uploadState) {
    final isUploading = uploadState is UploadInProgress;
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _loadMeta,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverList(delegate: SliverChildListDelegate([
              if (uploadState is UploadInProgress) _uploadProgressCard(uploadState),
              if (!isUploading)
                _mobileUploadBanner(isUploading)
                    .animate()
                    .fadeIn(duration: 400.ms)
                    .slideY(begin: 0.1, end: 0),
              const SizedBox(height: 16),

              // Storage ring card
              _glassCard(child: Column(children: [
                Center(
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: StorageRing(usedMb: _meta?.storageUsedMb ?? 0, limitMb: double.maxFinite),
                  ),
                ),
                const SizedBox(height: 12),
                _statRow(),
              ])).animate()
                  .fadeIn(duration: 400.ms, delay: 100.ms)
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: 20),

              // Categories header
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Categories', style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
              ]).animate()
                  .fadeIn(duration: 400.ms, delay: 200.ms)
                  .slideY(begin: 0.1, end: 0),
              const SizedBox(height: 12),
            ])),
          ),

          // Category grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  if (_meta == null) return const SizedBox.shrink();
                  final cats = [
                    _CatData('Images', Icons.image_rounded, _meta!.categories['images'] ?? CategoryStat(count: 0, sizeMb: 0),
                        const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)])),
                    _CatData('Videos', Icons.video_library_rounded, _meta!.categories['videos'] ?? CategoryStat(count: 0, sizeMb: 0),
                        const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFA855F7)])),
                    _CatData('Documents', Icons.description_rounded, _meta!.categories['docs'] ?? CategoryStat(count: 0, sizeMb: 0),
                        const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEF4444)])),
                    _CatData('Others', Icons.folder_rounded, _meta!.categories['others'] ?? CategoryStat(count: 0, sizeMb: 0),
                        const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF0088CC)])),
                  ];
                  return _CategoryCard(data: cats[i])
                      .animate()
                      .fadeIn(duration: 400.ms, delay: (200 + (i * 50)).ms)
                      .slideY(begin: 0.1, end: 0);
                },
                childCount: _meta == null ? 0 : 4,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
            ),
          ),

          // Recent files
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            sliver: SliverList(delegate: SliverChildListDelegate([
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Recent Files', style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed(AppRouter.browser),
                  child: Text('View All', style: TextStyle(color: AppTheme.primary,
                      fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ]),
              const SizedBox(height: 8),
              _recentFilesCard(),
            ])).animate()
                .fadeIn(duration: 400.ms, delay: 300.ms)
                .slideY(begin: 0.1, end: 0),
          ),
        ],
      ),
    );
  }

  Widget _mobileUploadBanner(bool isUploading) {
    return GestureDetector(
      onTap: isUploading ? null : _pickAndUpload,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primary, Color(0xFF8B5CF6), Color(0xFFA78BFA)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withAlpha(90),
              blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Stack(
          children: [
            // Shimmer overlay
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: [
                      Colors.white.withAlpha(0),
                      Colors.white.withAlpha(30),
                      Colors.white.withAlpha(0),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  blendMode: BlendMode.srcATop,
                  child: Container(color: Colors.white.withAlpha(8)),
                ),
              ),
            ),
            Row(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(35),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Upload a File',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 3),
                Text('Videos, images, docs — unlimited storage',
                    style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 12.5)),
              ])),
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────
  Widget _uploadProgressCard(UploadInProgress state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _glassCard(
        borderColor: AppTheme.primary.withAlpha(100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(state.status,
                  style: Theme.of(context).textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis),
            ),
            Text('${(state.progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 6,
              backgroundColor: isDark ? const Color(0xFF2A2A45) : const Color(0xFFE8E4FF),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _statRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hive = ServiceLocator.instance.isInitialized ? ServiceLocator.instance.hive : null;
    final div = Container(width: 1, height: 36,
        color: isDark ? const Color(0xFF2A2A45) : const Color(0xFFE0DFFF));
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _statPill(Icons.insert_drive_file_rounded, '${hive?.totalFiles ?? 0}', 'Files', AppTheme.primary),
      div,
      _statPill(Icons.cloud_done_outlined, _formatSize(_meta?.storageUsedMb ?? 0), 'Used', AppTheme.secondary),
      div,
      _statPill(Icons.all_inclusive_rounded, '∞', 'Limit', const Color(0xFF10B981)),
    ]);
  }

  Widget _statPill(IconData icon, String val, String sub, Color color) => Column(
    children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 4),
      Text(val, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      Text(sub, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _categoryGrid({required int crossAxisCount}) {
    if (_meta == null) return const SizedBox.shrink();
    final cats = [
      _CatData('Images', Icons.image_rounded, _meta!.categories['images'] ?? CategoryStat(count: 0, sizeMb: 0),
          const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)])),
      _CatData('Videos', Icons.video_library_rounded, _meta!.categories['videos'] ?? CategoryStat(count: 0, sizeMb: 0),
          const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFA855F7)])),
      _CatData('Documents', Icons.description_rounded, _meta!.categories['docs'] ?? CategoryStat(count: 0, sizeMb: 0),
          const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEF4444)])),
      _CatData('Others', Icons.folder_rounded, _meta!.categories['others'] ?? CategoryStat(count: 0, sizeMb: 0),
          const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF0088CC)])),
    ];
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: crossAxisCount == 4 ? 1.8 : 1.5,
      children: cats.map((c) => _CategoryCard(data: c)).toList(),
    );
  }

  Widget _recentFilesCard() {
    final files = ServiceLocator.instance.isInitialized
        ? ServiceLocator.instance.hive.recentFiles(5)
        : <dynamic>[];
    if (files.isEmpty) {
      return _glassCard(child: _emptyState());
    }
    return _glassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: files.asMap().entries.map((e) {
          final isLast = e.key == files.length - 1;
          return _RecentTile(
            file: e.value,
            isLast: isLast,
            onTap: () => _showDownloadOptions(e.value),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _showDownloadOptions(FileRecord file) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.file_present_rounded, color: AppTheme.primary, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(file.name,
                          style: Theme.of(context).textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(file.formattedSize, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppTheme.success),
              title: const Text('Download Directly', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Download and open the file immediately'),
              onTap: () {
                Navigator.pop(ctx);
                _downloadDirectly(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.downloading_rounded, color: AppTheme.primary),
              title: const Text('Download in Background', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Add to queue and download in background'),
              onTap: () {
                Navigator.pop(ctx);
                _downloadInBackground(file);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadDirectly(FileRecord file) async {
    final download = ServiceLocator.instance.downloadService;
    if (kIsWeb) {
      final notifier = ValueNotifier<({double progress, String status})>(
          (progress: 0.0, status: 'Starting…'));
      var dialogOpen = true;

      _showProgressDialog(file.name, notifier, () => dialogOpen = false);

      try {
        final bytes = await download.downloadFile(
          file, (p, s) { notifier.value = (progress: p, status: s); });
        
        if (dialogOpen && mounted) {
          Navigator.pop(context);
          dialogOpen = false;
        }

        await download.saveFile(bytes, file.name);
        _snack('✅ ${file.name} — download started!', success: true);
      } catch (e) {
        if (dialogOpen && mounted) Navigator.pop(context);
        _snack('❌ Download failed: $e');
      } finally {
        notifier.dispose();
      }
      return;
    }

    // Native: check file size (19 MB limit)
    if (file.sizeMb <= 19.0) {
      final notifier = ValueNotifier<({double progress, String status})>(
          (progress: 0.0, status: 'Starting…'));
      var dialogOpen = true;
      
      _showProgressDialog(file.name, notifier, () => dialogOpen = false);

      try {
        final bytes = await download.downloadFile(
          file, (p, s) { notifier.value = (progress: p, status: s); });
        
        notifier.value = (progress: 0.95, status: 'Saving file…');
        
        final saveResult = await download.saveAndOpen(bytes, file.name);
        
        if (dialogOpen && mounted) {
          Navigator.pop(context);
          dialogOpen = false;
        }

        if (saveResult.success) {
          await ServiceLocator.instance.downloadQueue.addCompletedJob(file, saveResult.savedPath);
          _snack('✅ Saved to downloads: ${file.name}', success: true);
        } else {
          _snack('❌ Save failed: ${saveResult.message}');
        }
      } catch (e) {
        if (dialogOpen && mounted) {
          Navigator.pop(context);
          dialogOpen = false;
        }
        _snack('❌ Download failed: $e');
      } finally {
        notifier.dispose();
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Download Large File'),
          content: Text(
            '"${file.name}" is a large file (${file.formattedSize}). '
            'Would you like to add it to the background downloads queue?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Download in Background', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmed == true && mounted) {
        _downloadInBackground(file);
      }
    }
  }

  Future<void> _downloadInBackground(FileRecord file) async {
    await ServiceLocator.instance.downloadQueue.enqueueDownload(file);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${file.name}" added to download queue'),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            final shell = MobileShell.of(context);
            if (shell != null) {
              shell.switchTab(2); // Downloads tab is index 2
            } else {
              Navigator.of(context).pushNamed(AppRouter.downloads);
            }
          },
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  void _showProgressDialog(String name, ValueNotifier<({double progress, String status})> notifier, VoidCallback onClosed) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder(
        valueListenable: notifier,
        builder: (context, state, __) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress == 0 ? null : state.progress,
                minHeight: 6,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            ),
            const SizedBox(height: 12),
            Text(state.status, style: Theme.of(context).textTheme.bodySmall),
            if (state.progress > 0) ...[
              const SizedBox(height: 4),
              Text('${(state.progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    ).then((_) => onClosed());
  }

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(children: [
      Container(
        width: 88, height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [AppTheme.primary.withAlpha(30), const Color(0xFFA78BFA).withAlpha(30)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.cloud_upload_outlined, size: 42, color: AppTheme.primary),
      ),
      const SizedBox(height: 20),
      ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          colors: [AppTheme.primary, Color(0xFFA78BFA)],
        ).createShader(bounds),
        child: Text('No files yet',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: Colors.white)),
      ),
      const SizedBox(height: 8),
      Text('Upload your first file to get started',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).textTheme.bodySmall?.color)),
      const SizedBox(height: 20),
      SizedBox(
        height: 44,
        child: ElevatedButton.icon(
          onPressed: _pickAndUpload,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Upload File', style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24),
          ),
        ),
      ),
    ]),
  );

  FloatingActionButton _buildFab(bool isUploading) => FloatingActionButton.extended(
    onPressed: isUploading ? null : _pickAndUpload,
    icon: const Icon(Icons.cloud_upload_rounded),
    label: const Text('Upload', style: TextStyle(fontWeight: FontWeight.w600)),
    backgroundColor: isUploading ? Colors.grey : AppTheme.primary,
    foregroundColor: Colors.white,
  );


  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _glassCard({required Widget child, EdgeInsetsGeometry? padding, Color? borderColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor ??
              (isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
        ),
      ),
      child: child,
    );
  }

  String _formatSize(double mb) {
    if (mb >= 1024 * 1024) return '${(mb / 1024 / 1024).toStringAsFixed(1)} TB';
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }
}

// ── Private data & widget classes ─────────────────────────────────────────────

class _CatData {
  final String name;
  final IconData icon;
  final CategoryStat stat;
  final Gradient gradient;
  const _CatData(this.name, this.icon, this.stat, this.gradient);
}

class _CategoryCard extends StatelessWidget {
  final _CatData data;
  const _CategoryCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              gradient: data.gradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 10),
          Text(data.name, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            '${data.stat.count} · ${_sz(data.stat.sizeMb)}',
            style: Theme.of(context).textTheme.bodySmall,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _sz(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }
}

class _RecentTile extends StatelessWidget {
  final dynamic file;
  final bool isLast;
  final VoidCallback onTap;
  const _RecentTile({required this.file, required this.isLast, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _color().withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon(), color: _color(), size: 22),
          ),
          title: Text(file.name,
              style: Theme.of(context).textTheme.labelLarge,
              overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${file.formattedSize} · ${_date(file.uploadedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.chevron_right_rounded, size: 20),
          onTap: onTap,
        ),
        if (!isLast)
          Divider(indent: 74, endIndent: 16, height: 1,
              color: isDark ? const Color(0xFF2A2A45) : const Color(0xFFE8E4FF)),
      ],
    );
  }

  IconData _icon() {
    final m = file.mimeType as String;
    if (m.startsWith('image/')) return Icons.image_rounded;
    if (m.startsWith('video/')) return Icons.video_file_rounded;
    if (m.startsWith('audio/')) return Icons.audio_file_rounded;
    if (m == 'application/pdf') return Icons.picture_as_pdf_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _color() {
    final m = file.mimeType as String;
    if (m.startsWith('image/')) return const Color(0xFF3B82F6);
    if (m.startsWith('video/')) return const Color(0xFFA855F7);
    if (m.startsWith('audio/')) return const Color(0xFFF59E0B);
    if (m == 'application/pdf') return const Color(0xFFEF4444);
    return AppTheme.primary;
  }

  String _date(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }
}
