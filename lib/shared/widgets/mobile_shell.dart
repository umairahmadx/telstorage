import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_file/open_file.dart';
import 'package:uuid/uuid.dart';

import '../../core/navigation/navigation_intent.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/service_locator.dart';
import '../../core/services/transfer_queue_service.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../features/browser/bloc/browser_bloc.dart';
import '../../features/browser/screens/browser_screen.dart';
import '../../features/downloads/screens/downloads_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/upload/bloc/upload_bloc.dart';
import 'app_drawer.dart';
import 'mobile_shell/mobile_add_action_item.dart';
import 'mobile_shell/mobile_bottom_nav.dart';

class MobileShell extends StatefulWidget {
  final int initialIndex;

  const MobileShell({super.key, this.initialIndex = 0});

  static MobileShellState? of(BuildContext context) {
    return context.findAncestorStateOfType<MobileShellState>();
  }

  @override
  State<MobileShell> createState() => MobileShellState();
}

class MobileShellState extends State<MobileShell> {
  late int _currentIndex;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    ServiceLocator.instance.navigation.intentNotifier
        .addListener(_onIntentChanged);
    NotificationService.instance.onNotificationTap = handleNotificationResponse;
  }

  @override
  void dispose() {
    ServiceLocator.instance.navigation.intentNotifier
        .removeListener(_onIntentChanged);
    super.dispose();
  }

  void _onIntentChanged() {
    final intent = ServiceLocator.instance.navigation.intentNotifier.value;
    if (intent != null) {
      setState(() {
        _currentIndex = intent.shellIndex;
      });
    }
  }

  void handleNotificationResponse(NotificationResponse details) {
    final payload = details.payload;
    final actionId = details.actionId;

    if (actionId != null) {
      if (actionId.startsWith('pause_')) {
        final id = actionId.replaceFirst('pause_', '');
        TransferQueueService.instance.pauseTask(id);
      } else if (actionId.startsWith('resume_')) {
        final id = actionId.replaceFirst('resume_', '');
        TransferQueueService.instance.resumeTask(id);
      } else if (actionId.startsWith('cancel_')) {
        final id = actionId.replaceFirst('cancel_', '');
        TransferQueueService.instance.cancelTask(id);
      } else if (actionId.startsWith('open_')) {
        final id = actionId.replaceFirst('open_', '');
        final job = ServiceLocator.instance.downloadQueue.allJobs
            .where((j) => j.fileId == id)
            .firstOrNull;
        if (job?.localPath != null) {
          OpenFile.open(job!.localPath!);
        }
      } else if (actionId.startsWith('copy_')) {
        final id = actionId.replaceFirst('copy_', '');
        final share = ServiceLocator.instance.webShareQueue.allShares
            .where((s) => s.fileId == id)
            .firstOrNull;
        if (share?.shareUrl != null) {
          Clipboard.setData(ClipboardData(text: share!.shareUrl!));
        }
      } else if (actionId == 'view_all') {
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferActive);
      }
      return;
    }

    if (payload == 'transfer_active') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferActive);
    } else if (details.payload == 'transfer_upload') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferUploads);
    } else if (details.payload == 'transfer_download') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferDownloads);
    } else if (details.payload == 'transfer_share') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferShared);
    }
  }

  void openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void switchTab(int index) {
    if (index == _currentIndex || index < 0 || index > 4) return;
    if (index == 2) {
      _showAddMenu();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  int get currentIndex => _currentIndex;

  void _showAddMenu() {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                AddActionItem(
                  icon: AppIcons.uploadFile,
                  label: 'Upload File',
                  color: AppTheme.primary,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUpload();
                  },
                ),
                if (_currentIndex == 1) // Only show in Files tab
                  AddActionItem(
                    icon: AppIcons.newFolder,
                    label: 'New Folder',
                    color: AppTheme.warning,
                    onTap: () {
                      Navigator.pop(ctx);
                      _showCreateFolderDialog();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateFolderDialog() async {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final ctrl = TextEditingController();
    final folderName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'New Folder',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: colors.textTertiary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.borderSubtle),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: colors.accentPrimary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accentPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Create', style: TextStyle(color: colors.bgPrimary)),
          ),
        ],
      ),
    );

    if (folderName != null && folderName.isNotEmpty && mounted) {
      context.read<BrowserBloc>().add(CreateFolder(folderName));
    }
  }

  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform
        .pickFiles(withData: true, allowMultiple: true);
    if (picked == null || picked.files.isEmpty) return;

    final List<UploadTask> tasks = [];
    const uuid = Uuid();
    for (final file in picked.files) {
      if (file.bytes == null) continue;
      tasks.add(UploadTask(
        id: uuid.v4(),
        bytes: file.bytes!,
        name: file.name,
      ));
    }

    if (tasks.isNotEmpty && mounted) {
      context.read<UploadBloc>().add(AddUploads(tasks));
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferUploads);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppDrawer(
        currentIndex: _currentIndex,
        onTabSelected: switchTab,
      ),
      body: IndexedStack(
        index: _currentIndex > 2
            ? _currentIndex - 1
            : (_currentIndex == 2 ? 0 : _currentIndex),
        children: const [
          HomeScreen(),
          BrowserScreen(),
          DownloadsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: MobileNavBar(
        currentIndex: _currentIndex,
        onTap: switchTab,
      ),
    );
  }
}
