import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/folder_record.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/thumbnail_widget.dart';
import '../../../shared/widgets/mobile_shell.dart';
import '../../../shared/widgets/share_link_sheet.dart';
import '../../../shared/widgets/file_detail_sheet.dart';
import '../bloc/browser_bloc.dart';
import '../../downloads/bloc/transfer_cubit.dart';

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
  @override
  void initState() {
    super.initState();
    context.read<BrowserBloc>().add(LoadDirectory(
        folderId: widget.currentFolderId, category: widget.category));
  }

  void _snack(String msg, {bool success = false}) {
    if (!mounted) return;
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? colors.success : colors.error,
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
    final existing = context.read<TransferCubit>().getShareJob(file.fileId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareLinkSheet(
        file: file,
        shareUrl: existing?.shareUrl,
        onCopyLink: (pwd, expiryDays) async {
          context
              .read<BrowserBloc>()
              .add(EnqueueShare(file, password: pwd, expiryDays: expiryDays));

          if (!mounted || !ctx.mounted) return;
          Navigator.pop(ctx);

          _snack('Sharing started. Check "Transfer" tab for progress.',
              success: true);
        },
      ),
    );
  }

  Future<void> _renameFile(FileRecord file) async {
    final ctrl = TextEditingController(text: file.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Rename File'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      context.read<BrowserBloc>().add(RenameFile(file.fileId, result));
    }
  }

  Future<void> _deleteFile(FileRecord file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Delete "${file.name}"?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) context.read<BrowserBloc>().add(DeleteFile(file.fileId));
  }

  Future<void> _downloadAndView(FileRecord file) async {
    context.read<BrowserBloc>().add(EnqueueDownload(file));
    _snack('"${file.name}" added to downloads', success: true);
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('New Folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      context.read<BrowserBloc>().add(CreateFolder(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BrowserBloc, BrowserState>(
      listener: (context, state) {
        if (state.errorMessage != null) _snack(state.errorMessage!);
      },
      builder: (context, state) {
        if (state.isLoading && !state.isInitialized) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        return PopScope(
          canPop: state.currentFolderId == null && state.category == null,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            context.read<BrowserBloc>().add(NavigateUp());
          },
          child: _buildScaffold(context, state),
        );
      },
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
          _buildFilterTabs(colors, state),
          const SizedBox(height: 12),
          if (state.isLoading && state.isInitialized)
             const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _buildSectionHeader('Folders',
                    trailing: IconButton(
                      icon:
                          Icon(Icons.add, size: 20, color: colors.textPrimary),
                      onPressed: _createFolder,
                    )),
                ...state.folders.map((f) {
                  final count = state.folderItemCounts[f.id] ?? 0;
                  return _FolderTile(
                    folder: f,
                    itemCount: count,
                    onTap: () {
                      context.read<BrowserBloc>().add(LoadDirectory(folderId: f.id));
                    },
                    onMore: () {
                      // Folder more actions
                    },
                  );
                }),
                const SizedBox(height: 24),
                _buildSectionHeader('Files',
                    trailing: GestureDetector(
                      onTap: () =>
                          context.read<BrowserBloc>().add(SortOptionChanged(BrowserSortOption.name)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Name',
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 13)),
                          const SizedBox(width: 4),
                          Icon(
                              state.sortAscending
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 14,
                              color: colors.textSecondary),
                        ],
                      ),
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
          onChanged: (v) => context.read<BrowserBloc>().add(SearchQueryChanged(v)),
          style: TextStyle(color: colors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search files and folders...',
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

  Widget _buildFilterTabs(AppColorsExtension colors, BrowserState state) {
    final filters = [
      {'label': 'All', 'key': null},
      {'label': 'Images', 'key': 'images'},
      {'label': 'Videos', 'key': 'videos'},
      {'label': 'Docs', 'key': 'docs'},
      {'label': 'Audio', 'key': 'others'},
    ];

    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: filters.length,
        itemBuilder: (ctx, i) {
          final filter = filters[i];
          final isSelected = state.category == filter['key'];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () {
                context.read<BrowserBloc>().add(LoadDirectory(
                    folderId: state.currentFolderId, category: filter['key']));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: isSelected ? colors.accentPrimary : colors.bgSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  filter['label'] as String,
                  style: TextStyle(
                    color: isSelected ? (Theme.of(context).brightness == Brightness.dark ? Colors.black : Colors.white) : colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
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
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final FolderRecord folder;
  final int itemCount;
  final VoidCallback onTap;
  final VoidCallback onMore;
  const _FolderTile(
      {required this.folder,
      required this.itemCount,
      required this.onTap,
      required this.onMore});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final dateStr = DateFormat('dd MMM yyyy').format(folder.createdAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.fileFolderBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.folder_rounded,
                  color: colors.fileFolder, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(folder.name,
                      style: Theme.of(context).textTheme.titleLarge),
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
                Text(file.name,
                    style: Theme.of(context).textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
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
            fallback: Container(
                color: colors.bgSurface,
                child: Icon(Icons.image, color: colors.textPrimary.withAlpha(60))),
          ),
        ),
      );
    }

    if (file.name.endsWith('.fig')) {
      return Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: colors.bgSurfaceInset,
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child:
            Icon(Icons.palette_outlined, color: colors.filePalette, size: 26),
      );
    }

    Color bgColor = colors.fileGenericBg;
    Widget icon;

    if (file.isPdf) {
      bgColor = colors.filePdfBg;
      icon = Text('PDF',
          style: TextStyle(
              color: colors.filePdf, fontWeight: FontWeight.bold, fontSize: 12));
    } else if (file.isVideo) {
      bgColor = colors.fileVideoBg;
      icon = Icon(Icons.play_arrow_rounded,
          color: colors.fileVideo, size: 30);
    } else if (mime.startsWith('text/')) {
      bgColor = colors.fileTextBg;
      icon = Icon(Icons.description_rounded,
          color: colors.filePdf, size: 26);
    } else {
      icon = Icon(Icons.insert_drive_file_rounded,
          color: colors.textTertiary, size: 26);
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
