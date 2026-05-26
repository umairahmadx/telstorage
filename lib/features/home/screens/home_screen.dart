import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/models/app_metadata.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/hive_service.dart';
import '../../../core/services/telegram_service.dart';
import '../../../core/services/metadata_service.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/services/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/responsive.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/storage_ring.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _telegram = TelegramService();
  late final MetadataService _metadata;
  late final UploadService _upload;
  late final SyncService _sync;
  final _hive = HiveService.instance;

  AppMetadata? _meta;
  bool _isLoading    = true;
  bool _isSyncing    = false;
  String _syncStatus = '';
  bool _isUploading  = false;
  double _uploadPct  = 0;
  String _uploadStatus = '';

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      final token     = await AuthService.instance.getToken();
      final channelId = await AuthService.instance.getChannelId();
      if (token == null || channelId == null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AppRouter.login);
        return;
      }
      await _telegram.init(token, channelId);
      _metadata = MetadataService(_telegram);
      _upload   = UploadService(_telegram, _metadata, _hive);
      _sync     = SyncService(_metadata, _telegram, _hive);
      await _syncFromTelegram();
    } catch (e) {
      if (!mounted) return;
      _snack('Error initializing: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncFromTelegram() async {
    setState(() { _isLoading = true; _isSyncing = true; _syncStatus = 'Syncing…'; });
    SyncResult? result;
    try {
      result = await _sync.syncFromTelegram(
        onProgress: (_, s) { if (mounted) setState(() => _syncStatus = s); },
      );
    } catch (_) {}
    finally {
      if (mounted) setState(() => _isSyncing = false);
    }
    await _loadMeta();
    if (result != null && result.hasChanges && mounted) {
      final parts = <String>[];
      if (result.added > 0)   parts.add('+${result.added} new');
      if (result.removed > 0) parts.add('-${result.removed} removed');
      _snack('Synced: ${parts.join(', ')}', success: true);
    }
  }

  Future<void> _loadMeta() async {
    setState(() => _isLoading = true);
    try {
      final m = await _metadata.fetch();
      setState(() { _meta = m; _isLoading = false; });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      String msg = 'Sync error: $e';
      if (e.toString().contains('No pinned')) msg = 'Initializing storage… Retry.';
      _snack(msg);
    }
  }

  Future<void> _pickAndUpload() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) { _snack('Could not read file'); return; }

    setState(() { _isUploading = true; _uploadPct = 0; _uploadStatus = 'Starting…'; });
    try {
      await _upload.uploadFile(
        file.bytes!, file.name, null,
        (p, s) { if (mounted) setState(() { _uploadPct = p; _uploadStatus = s; }); },
      );
      _snack('✅ ${file.name} uploaded!', success: true);
      await _loadMeta();
    } catch (e) {
      _snack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
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
    final content  = _isLoading ? _buildLoading() : _buildContent();

    if (isMobile) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: _mobileAppBar(),
        body: content,
        floatingActionButton: _buildFab(),
        bottomNavigationBar: _buildBottomNav(),
      );
    }

    // Desktop: shell wraps content
    return AppShell(
      selectedIndex: 0,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: _desktopTopBar(),
        body: content,
        floatingActionButton: _buildFab(),
      ),
    );
  }

  PreferredSizeWidget _mobileAppBar() => PreferredSize(
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
          child: Row(children: [
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
                Text(_isSyncing ? _syncStatus : 'Your cloud drive',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (_isSyncing)
              const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))
            else
              IconButton(
                icon: const Icon(Icons.sync_rounded, size: 22),
                tooltip: 'Sync',
                onPressed: _syncFromTelegram,
              ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, size: 22),
              onPressed: () => Navigator.of(context).pushNamed(AppRouter.settings),
            ),
          ]),
        ),
      ),
    ),
  );

  AppBar _desktopTopBar() => AppBar(
    automaticallyImplyLeading: false,
    title: Text('Dashboard', style: Theme.of(context).textTheme.headlineSmall),
    actions: [
      if (_isSyncing)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(children: [
            const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
            const SizedBox(width: 8),
            Text(_syncStatus, style: Theme.of(context).textTheme.bodySmall),
          ]),
        )
      else
        TextButton.icon(
          onPressed: _syncFromTelegram,
          icon: const Icon(Icons.sync_rounded, size: 18),
          label: const Text('Sync'),
          style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
        ),
      const SizedBox(width: 8),
    ],
  );

  Widget _buildLoading() {
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
        Text(_syncStatus.isEmpty ? 'Loading…' : _syncStatus,
            style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }

  Widget _buildContent() {
    final isDesktop = Responsive.isDesktop(context);
    return isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
  }

  // ── DESKTOP LAYOUT ────────────────────────────────────────────────────────
  Widget _buildDesktopLayout() {
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _loadMeta,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
        child: Column(children: [
          // Upload progress
          if (_isUploading) _uploadProgressCard(),
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
                        onPressed: _isUploading ? null : _pickAndUpload,
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
  Widget _buildMobileLayout() {
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: _loadMeta,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverList(delegate: SliverChildListDelegate([
              if (_isUploading) _uploadProgressCard(),

              // Upload CTA banner
              if (!_isUploading) _mobileUploadBanner(),
              const SizedBox(height: 16),

              // Storage ring card
              _glassCard(child: Column(children: [
                StorageRing(usedMb: _meta?.storageUsedMb ?? 0, limitMb: double.maxFinite),
                const SizedBox(height: 12),
                _statRow(),
              ])),
              const SizedBox(height: 20),

              // Categories header
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Categories', style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
              ]),
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
                    _CatData('Images', Icons.image_rounded, _meta!.categories['images']!,
                        const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)])),
                    _CatData('Videos', Icons.video_library_rounded, _meta!.categories['videos']!,
                        const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFA855F7)])),
                    _CatData('Documents', Icons.description_rounded, _meta!.categories['docs']!,
                        const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEF4444)])),
                    _CatData('Others', Icons.folder_rounded, _meta!.categories['others']!,
                        const LinearGradient(colors: [Color(0xFF10B981), Color(0xFF0088CC)])),
                  ];
                  return _CategoryCard(data: cats[i]);
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
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
            ])),
          ),
        ],
      ),
    );
  }

  Widget _mobileUploadBanner() {
    return GestureDetector(
      onTap: _isUploading ? null : _pickAndUpload,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primary, Color(0xFF8B5CF6)],
            begin: Alignment.centerLeft, end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: AppTheme.primary.withAlpha(80),
            blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Upload a File',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
            const Text('Videos, images, docs, anything',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
        ]),
      ),
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────
  Widget _uploadProgressCard() {
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
              child: Text(_uploadStatus,
                  style: Theme.of(context).textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis),
            ),
            Text('${(_uploadPct * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _uploadPct,
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
    final div = Container(width: 1, height: 36,
        color: isDark ? const Color(0xFF2A2A45) : const Color(0xFFE0DFFF));
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _statPill(Icons.insert_drive_file_rounded, '${_hive.totalFiles}', 'Files', AppTheme.primary),
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
      _CatData('Images', Icons.image_rounded, _meta!.categories['images']!,
          const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)])),
      _CatData('Videos', Icons.video_library_rounded, _meta!.categories['videos']!,
          const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFA855F7)])),
      _CatData('Documents', Icons.description_rounded, _meta!.categories['docs']!,
          const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEF4444)])),
      _CatData('Others', Icons.folder_rounded, _meta!.categories['others']!,
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
    final files = _hive.recentFiles(5);
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
            onTap: () => Navigator.of(context).pushNamed(AppRouter.browser),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(25), shape: BoxShape.circle),
        child: const Icon(Icons.cloud_upload_outlined, size: 36, color: AppTheme.primary),
      ),
      const SizedBox(height: 16),
      Text('No files yet', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text('Tap the Upload button to get started',
          style: Theme.of(context).textTheme.bodySmall),
    ]),
  );

  FloatingActionButton _buildFab() => FloatingActionButton.extended(
    onPressed: _isUploading ? null : _pickAndUpload,
    icon: const Icon(Icons.cloud_upload_rounded),
    label: const Text('Upload', style: TextStyle(fontWeight: FontWeight.w600)),
    backgroundColor: _isUploading ? Colors.grey : AppTheme.primary,
    foregroundColor: Colors.white,
  );

  Widget _buildBottomNav() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        border: Border(top: BorderSide(
            color: isDark ? const Color(0xFF2A2A45) : const Color(0xFFE0DFFF))),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 40 : 15),
              blurRadius: 20, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(children: [
            _BottomNavItem(Icons.home_rounded, 'Home', true, () {}),
            _BottomNavItem(Icons.folder_rounded, 'Files', false,
                () => Navigator.of(context).pushNamed(AppRouter.browser)),
            _BottomNavItem(Icons.settings_outlined, 'Settings', false,
                () => Navigator.of(context).pushNamed(AppRouter.settings)),
          ]),
        ),
      ),
    );
  }

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

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _BottomNavItem(this.icon, this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary.withAlpha(25) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon,
                color: selected ? AppTheme.primary : Colors.grey, size: 23),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppTheme.primary : Colors.grey)),
        ]),
      ),
    );
  }
}
