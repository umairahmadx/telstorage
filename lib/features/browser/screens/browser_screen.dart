import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/folder_record.dart';
import '../../../core/services/service_locator.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/responsive.dart';
import '../../../shared/widgets/app_shell.dart';
import '../../../shared/widgets/thumbnail_widget.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../shared/widgets/share_link_sheet.dart';
import '../../../shared/widgets/file_detail_sheet.dart';
import '../bloc/browser_bloc.dart';

enum BrowserSortOption { name, date, size }
enum BrowserGroupOption { foldersFirst, fileCategory, none }

class BrowserScreen extends StatefulWidget {
  final String? currentFolderId;
  final String? category;
  const BrowserScreen({super.key, this.currentFolderId, this.category});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final BrowserBloc _bloc;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _bloc = BrowserBloc();
    _initServices();
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  Future<void> _initServices() async {
    try {
      await ServiceLocator.instance.init();
      if (mounted) {
        setState(() => _isLoading = false);
        _bloc.add(LoadDirectory(folderId: widget.currentFolderId, category: widget.category));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRouter.login);
    }
  }

  void _snack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green : AppTheme.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
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
          _downloadAndView(file);
        },
        onRename: () {
          Navigator.pop(ctx);
          _renameFile(file);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _deleteFile(file);
        },
      ),
    );
  }

  void _showShareSheet(FileRecord file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: file,
        onCopyLink: (pwd, expiry) {
          if (!mounted) return;
          Navigator.pop(ctx);
          _snack('Link copied with $expiry validity', success: true);
        },
      ),
    );
  }

  Future<void> _renameFile(FileRecord file) async {
    final ctrl = TextEditingController(text: file.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Rename File'),
        content: TextField(
          controller: ctrl, 
          autofocus: true,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) _bloc.add(RenameFile(file.fileId, result));
  }

  Future<void> _deleteFile(FileRecord file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Delete "${file.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) _bloc.add(DeleteFile(file.fileId));
  }

  Future<void> _downloadAndView(FileRecord file) async {
    await ServiceLocator.instance.downloadQueue.enqueueDownload(file);
    _snack('"${file.name}" added to downloads', success: true);
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('New Folder'),
        content: TextField(
          controller: ctrl, 
          autofocus: true,
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) _bloc.add(CreateFolder(result));
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return BlocProvider.value(
      value: _bloc,
      child: BlocConsumer<BrowserBloc, BrowserState>(
        listener: (context, state) {
          if (state.errorMessage != null) _snack(state.errorMessage!);
        },
        builder: (context, state) {
          if (_isLoading || (state.isLoading && state.folders.isEmpty && state.files.isEmpty)) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          final scaffold = _buildScaffold(context, state);
          if (isMobile) return scaffold;
          return AppShell(selectedIndex: 1, child: scaffold);
        },
      ),
    );
  }

  Widget _buildScaffold(BuildContext context, BrowserState state) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Scaffold(
      backgroundColor: colors.bgPrimary,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => MobileShell.of(context)?.openDrawer(),
        ),
        title: const Text('Files'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => MobileShell.of(context)?.switchTab(3),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(colors),
          _buildFilterTabs(colors),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildSectionHeader('Folders', trailing: IconButton(
                  icon: const Icon(Icons.add, size: 20, color: Colors.white),
                  onPressed: _createFolder,
                )),
                ...state.folders.map((f) {
                   final count = ServiceLocator.instance.hive.filesInFolder(f.id).length;
                   return _FolderTile(
                    folder: f,
                    itemCount: count,
                    onMore: () {
                      // Folder more actions
                    },
                  );
                }),
                const SizedBox(height: 24),
                _buildSectionHeader('Files', trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Name', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_downward_rounded, size: 14, color: colors.textSecondary),
                  ],
                )),
                ...state.files.map((f) => _FileTile(
                  file: f,
                  onMore: () => _showFileDetail(f),
                )),
                const SizedBox(height: 100),
              ],
            ),
          ),
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
          onChanged: (v) => _bloc.add(SearchQueryChanged(v)),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search files and folders...',
            hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded, color: colors.textTertiary, size: 20),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTabs(AppColorsExtension colors) {
    final filters = ['All', 'Images', 'Videos', 'Docs', 'Audio'];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (ctx, i) {
          final isAll = i == 0;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isAll ? colors.accentPrimary : colors.bgSurface,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                filters[i],
                style: TextStyle(
                  color: isAll ? Colors.black : colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final FolderRecord folder;
  final int itemCount;
  final VoidCallback onMore;
  const _FolderTile({required this.folder, required this.itemCount, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM yyyy').format(folder.createdAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFDE9C9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.folder_rounded, color: Color(0xFFF5A623), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(folder.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Text(
                  '$itemCount items • $dateStr',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.more_horiz_rounded, color: colors.textTertiary),
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final FileRecord file;
  final VoidCallback onMore;
  const _FileTile({required this.file, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM yyyy').format(file.uploadedAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          _buildLeading(colors),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${file.formattedSize} • $dateStr',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.more_horiz_rounded, color: colors.textTertiary),
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
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 52,
          height: 52,
          child: ThumbnailWidget(
            file: file,
            width: 52,
            height: 52,
            fallback: Container(color: colors.bgSurface, child: const Icon(Icons.image, color: Colors.white24)),
          ),
        ),
      );
    }

    if (file.name.endsWith('.fig')) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1D),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.palette_outlined, color: Colors.purple, size: 26),
      );
    }

    Color bgColor = const Color(0xFF1A1A1E);
    Widget icon;

    if (mime == 'application/pdf') {
      bgColor = const Color(0xFF2C0E0E);
      icon = const Text('PDF', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12));
    } else if (mime.startsWith('video/')) {
      bgColor = const Color(0xFF10142D);
      icon = const Icon(Icons.play_arrow_rounded, color: Color(0xFF5B7FFF), size: 30);
    } else if (mime.startsWith('text/')) {
      bgColor = const Color(0xFF0D172D);
      icon = const Icon(Icons.description_rounded, color: Color(0xFF4A6CF7), size: 26);
    } else {
      icon = const Icon(Icons.insert_drive_file_rounded, color: Colors.white38, size: 26);
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }
}
