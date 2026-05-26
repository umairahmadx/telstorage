import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/utils/file_reader_native.dart'
    if (dart.library.js_interop) '../../../core/utils/file_reader_stub.dart';
import '../../../core/models/file_record.dart';
import '../../../core/models/folder_record.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/hive_service.dart';
import '../../../core/services/telegram_service.dart';
import '../../../core/services/metadata_service.dart';
import '../../../core/services/file_manager.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/services/download_service.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/utils/responsive.dart';
import '../../../shared/widgets/app_shell.dart';

class BrowserScreen extends StatefulWidget {
  final String? currentFolderId;
  const BrowserScreen({super.key, this.currentFolderId});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _hive = HiveService.instance;
  final _telegram = TelegramService();
  late final MetadataService _metadata;
  late final FileManagerService _fileManager;
  late final DownloadService _download;
  late final UploadService _upload;

  bool _isLoading = true;
  String _search = '';
  bool _gridView = false;
  bool _fabOpen = false;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    try {
      final token = await AuthService.instance.getToken();
      final channelId = await AuthService.instance.getChannelId();
      if (token == null || channelId == null) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AppRouter.login);
        return;
      }
      await _telegram.init(token, channelId);
      _metadata = MetadataService(_telegram);
      _fileManager = FileManagerService(_metadata, _telegram, _hive);
      _download = DownloadService(_telegram);
      _upload = UploadService(_telegram, _metadata, _hive);
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      _snack('Error: $e');
    }
  }

  Future<void> _createFolder() async {
    final ctrl = TextEditingController();
    final result = await _showInputDialog('New Folder', 'Folder name', ctrl);
    if (result == null || result.isEmpty) return;
    try {
      await _fileManager.createFolder(result, parentId: widget.currentFolderId);
      setState(() {});
      _snack('Folder created', success: true);
    } catch (e) {
      _snack('Error: $e');
    }
  }

  Future<String?> _showInputDialog(String title, String label, TextEditingController ctrl) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
    final scaffold = _buildScaffold();
    if (isMobile) return scaffold;
    return AppShell(selectedIndex: 1, child: scaffold);
  }

  Scaffold _buildScaffold() {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppTheme.primary),
          ),
        ),
      );
    }

    final rawFolders = _hive.subfolders(widget.currentFolderId);
    final rawFiles   = _hive.filesInFolder(widget.currentFolderId);
    final q = _search.toLowerCase();
    final folders = q.isEmpty
        ? rawFolders
        : rawFolders.where((f) => f.name.toLowerCase().contains(q)).toList();
    final files = q.isEmpty
        ? rawFiles
        : rawFiles.where((f) => f.name.toLowerCase().contains(q)).toList();

    return Scaffold(
      appBar: _buildAppBar(folders.length + files.length),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: folders.isEmpty && files.isEmpty
                ? _buildEmpty()
                : _buildList(folders, files),
          ),
        ],
      ),
      floatingActionButton: _buildSpeedDial(),
    );
  }

  AppBar _buildAppBar(int count) {
    return AppBar(
      leading: widget.currentFolderId != null ? const BackButton() : null,
      automaticallyImplyLeading: widget.currentFolderId != null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.currentFolderId == null ? 'All Files' : 'Folder'),
          if (count > 0)
            Text('$count items',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(_gridView ? Icons.list_rounded : Icons.grid_view_rounded),
          tooltip: _gridView ? 'List view' : 'Grid view',
          onPressed: () => setState(() => _gridView = !_gridView),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search files and folders…',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          filled: true,
          fillColor: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppTheme.primary.withAlpha(25), shape: BoxShape.circle),
          child: const Icon(Icons.folder_open_rounded, size: 40, color: AppTheme.primary),
        ),
        const SizedBox(height: 16),
        Text(_search.isEmpty ? 'No files or folders' : 'No results for "$_search"',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('Upload files from the Home screen',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget _buildList(List<FolderRecord> folders, List<FileRecord> files) {
    if (_gridView) return _buildGrid(folders, files);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        if (folders.isNotEmpty) ...[
          _sectionLabel('Folders (${folders.length})'),
          ...folders.map((f) => _FolderTile(
            folder: f,
            onTap: () => Navigator.of(context).pushNamed(AppRouter.browser, arguments: f.id),
            onRename: () => _renameFolder(f),
            onDelete: () => _deleteFolder(f),
          )),
          const SizedBox(height: 16),
        ],
        if (files.isNotEmpty) ...[
          _sectionLabel('Files (${files.length})'),
          ...files.map((f) => _FileTile(
            file: f,
            onTap: () => _downloadAndView(f),
            onRename: () => _renameFile(f),
            onDelete: () => _deleteFile(f),
          )),
        ],
      ],
    );
  }

  Widget _buildGrid(List<FolderRecord> folders, List<FileRecord> files) {
    final isMobile = Responsive.isMobile(context);
    final cols = isMobile ? 3 : 5;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.9,
      ),
      itemCount: folders.length + files.length,
      itemBuilder: (ctx, i) {
        if (i < folders.length) {
          final f = folders[i];
          return _GridFolderItem(folder: f,
            onTap: () => Navigator.of(context).pushNamed(AppRouter.browser, arguments: f.id),
            onRename: () => _renameFolder(f),
            onDelete: () => _deleteFolder(f),
          );
        }
        final f = files[i - folders.length];
        return _GridFileItem(file: f,
          onTap: () => _downloadAndView(f),
          onRename: () => _renameFile(f),
          onDelete: () => _deleteFile(f),
        );
      },
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4, left: 2),
    child: Text(text.toUpperCase(),
        style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: AppTheme.primary, letterSpacing: 1.1)),
  );

  Future<void> _renameFolder(FolderRecord folder) async {
    final ctrl = TextEditingController(text: folder.name);
    final result = await _showInputDialog('Rename Folder', 'New name', ctrl);
    if (result == null || result.isEmpty) return;
    try { await _fileManager.renameFolder(folder.id, result); setState(() {}); }
    catch (e) { _snack('Error: $e'); }
  }

  Future<void> _deleteFolder(FolderRecord folder) async {
    final ok = await _confirm('Delete "${folder.name}"?', 'This cannot be undone.');
    if (!ok) return;
    try { await _fileManager.deleteFolder(folder.id); setState(() {}); }
    catch (e) { _snack('Error: $e'); }
  }

  Future<void> _renameFile(FileRecord file) async {
    final ctrl = TextEditingController(text: file.name);
    final result = await _showInputDialog('Rename File', 'New name', ctrl);
    if (result == null || result.isEmpty) return;
    try { await _fileManager.renameFile(file.fileId, result); setState(() {}); }
    catch (e) { _snack('Error: $e'); }
  }

  Future<void> _deleteFile(FileRecord file) async {
    final ok = await _confirm('Delete "${file.name}"?', 'This cannot be undone.');
    if (!ok) return;
    try {
      await _fileManager.deleteFile(file.fileId);
      setState(() {});
      _snack('File deleted', success: true);
    } catch (e) { _snack('Error: $e'); }
  }

  Future<bool> _confirm(String title, String body) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _downloadAndView(FileRecord file) async {
    final notifier = ValueNotifier<({double progress, String status})>(
        (progress: 0.0, status: 'Starting…'));
    var dialogOpen = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder(
        valueListenable: notifier,
        builder: (_, state, __) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(file.name,
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
    ).then((_) => dialogOpen = false);

    void closeDialog() {
      if (dialogOpen && mounted) { dialogOpen = false; Navigator.pop(context); }
    }

    try {
      final bytes = await _download.downloadFile(
        file, (p, s) { notifier.value = (progress: p, status: s); });
      closeDialog();
      if (!mounted) return;

      if (kIsWeb) {
        // Web: browser download bar
        await _download.saveFile(bytes, file.name);
        _snack('✅ ${file.name} — download started!', success: true);
      } else {
        // Android/iOS: save to Downloads / Files app
        notifier.value = (progress: 1.0, status: 'Saving to device…');
        final result = await _download.saveAndOpen(bytes, file.name);
        if (!mounted) return;
        _snack(result.message, success: result.success);
      }
    } catch (e) {
      closeDialog();
      if (!mounted) return;
      _snack('❌ Download failed: $e');
    } finally {
      notifier.dispose();
    }
  }

  // ── Speed Dial FAB ─────────────────────────────────────────────────────────

  Widget _buildSpeedDial() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabOpen) ...[
          _MiniAction(
            icon: Icons.upload_file_rounded,
            label: 'Upload File',
            color: const Color(0xFF10B981),
            onTap: () { setState(() => _fabOpen = false); _uploadFile(); },
          ),
          const SizedBox(height: 8),
          _MiniAction(
            icon: Icons.create_new_folder_rounded,
            label: 'New Folder',
            color: const Color(0xFFF59E0B),
            onTap: () { setState(() => _fabOpen = false); _createFolder(); },
          ),
          const SizedBox(height: 8),
        ],
        FloatingActionButton(
          onPressed: () => setState(() => _fabOpen = !_fabOpen),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          child: AnimatedRotation(
            duration: const Duration(milliseconds: 200),
            turns: _fabOpen ? 0.125 : 0,
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        ),
      ],
    );
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    if (picked.bytes == null && picked.path == null) {
      _snack('Could not read file'); return;
    }

    final notifier = ValueNotifier<({double progress, String status})>(
        (progress: 0.0, status: 'Preparing…'));
    var dialogOpen = true;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder(
        valueListenable: notifier,
        builder: (_, state, __) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Uploading ${picked.name}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: state.progress == 0 ? null : state.progress,
                minHeight: 6,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              ),
            ),
            const SizedBox(height: 12),
            Text(state.status, style: Theme.of(context).textTheme.bodySmall),
            if (state.progress > 0) ...[
              const SizedBox(height: 4),
              Text('${(state.progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    ).then((_) => dialogOpen = false);

    void closeDialog() {
      if (dialogOpen && mounted) { dialogOpen = false; Navigator.pop(context); }
    }

    try {
      final Uint8List bytes;
      if (picked.bytes != null) {
        bytes = picked.bytes!;
      } else if (!kIsWeb && picked.path != null) {
        // Native: read bytes from path (dart:io safe since kIsWeb=false)
        bytes = await _readNativeFile(picked.path!);
      } else {
        _snack('Cannot read file on this platform'); return;
      }
      await _upload.uploadFile(
        bytes, picked.name, widget.currentFolderId,
        (p, s) => notifier.value = (progress: p, status: s),
      );
      closeDialog();
      if (!mounted) return;
      setState(() {});
      _snack('✅ ${picked.name} uploaded!', success: true);
    } catch (e) {
      closeDialog();
      if (!mounted) return;
      _snack('❌ Upload failed: $e');
    } finally {
      notifier.dispose();
    }
  }

  /// Read file bytes from native path — only call when kIsWeb == false.
  Future<Uint8List> _readNativeFile(String path) => readFileBytes(path);
}

// ── Mini FAB action button ───────────────────────────────────────────────────

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MiniAction({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 4,
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Material(
          elevation: 4,
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Tile Widgets ──────────────────────────────────────────────────────────────

class _FileTile extends StatelessWidget {
  final FileRecord file;
  final VoidCallback onTap, onRename, onDelete;
  const _FileTile({required this.file, required this.onTap,
      required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
      ),
      child: ListTile(
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: _color().withAlpha(25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_icon(), color: _color(), size: 22),
        ),
        title: Text(file.name, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge),
        subtitle: Text('${file.formattedSize} · ${_date(file.uploadedAt)}',
            style: Theme.of(context).textTheme.bodySmall),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (v) { if (v == 'rename') onRename(); else if (v == 'delete') onDelete(); },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Row(children: [
              Icon(Icons.edit_rounded, size: 18), SizedBox(width: 10), Text('Rename')])),
            const PopupMenuItem(value: 'delete', child: Row(children: [
              Icon(Icons.delete_rounded, size: 18, color: Colors.red),
              SizedBox(width: 10),
              Text('Delete', style: TextStyle(color: Colors.red))])),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  IconData _icon() {
    if (file.isImage) return Icons.image_rounded;
    if (file.isVideo) return Icons.video_file_rounded;
    if (file.isAudio) return Icons.audio_file_rounded;
    if (file.isPdf)   return Icons.picture_as_pdf_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _color() {
    if (file.isImage) return const Color(0xFF3B82F6);
    if (file.isVideo) return const Color(0xFFA855F7);
    if (file.isAudio) return const Color(0xFFF59E0B);
    if (file.isPdf)   return const Color(0xFFEF4444);
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

class _FolderTile extends StatelessWidget {
  final FolderRecord folder;
  final VoidCallback onTap, onRename, onDelete;
  const _FolderTile({required this.folder, required this.onTap,
      required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
      ),
      child: ListTile(
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withAlpha(25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.folder_rounded,
              color: Color(0xFFF59E0B), size: 24),
        ),
        title: Text(folder.name, style: Theme.of(context).textTheme.labelLarge),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, size: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (v) { if (v == 'rename') onRename(); else if (v == 'delete') onDelete(); },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Row(children: [
              Icon(Icons.edit_rounded, size: 18), SizedBox(width: 10), Text('Rename')])),
            const PopupMenuItem(value: 'delete', child: Row(children: [
              Icon(Icons.delete_rounded, size: 18, color: Colors.red),
              SizedBox(width: 10),
              Text('Delete', style: TextStyle(color: Colors.red))])),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _GridFileItem extends StatelessWidget {
  final FileRecord file;
  final VoidCallback onTap, onRename, onDelete;
  const _GridFileItem({required this.file, required this.onTap,
      required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
        ),
        child: Column(children: [
          Expanded(child: Center(child: Icon(_icon(), size: 40, color: _color()))),
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(file.name, overflow: TextOverflow.ellipsis,
                maxLines: 2, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ),
    );
  }
  IconData _icon() {
    if (file.isImage) return Icons.image_rounded;
    if (file.isVideo) return Icons.video_file_rounded;
    if (file.isAudio) return Icons.audio_file_rounded;
    if (file.isPdf)   return Icons.picture_as_pdf_rounded;
    return Icons.insert_drive_file_rounded;
  }
  Color _color() {
    if (file.isImage) return const Color(0xFF3B82F6);
    if (file.isVideo) return const Color(0xFFA855F7);
    return AppTheme.primary;
  }
}

class _GridFolderItem extends StatelessWidget {
  final FolderRecord folder;
  final VoidCallback onTap, onRename, onDelete;
  const _GridFolderItem({required this.folder, required this.onTap,
      required this.onRename, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? AppTheme.darkCardBorder : AppTheme.lightCardBorder),
        ),
        child: Column(children: [
          const Expanded(child: Center(child:
              Icon(Icons.folder_rounded, size: 40, color: Color(0xFFF59E0B)))),
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text(folder.name, overflow: TextOverflow.ellipsis,
                maxLines: 2, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ),
    );
  }
}
