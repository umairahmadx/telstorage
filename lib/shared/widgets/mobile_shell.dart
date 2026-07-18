import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/services/service_locator.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/transfer_queue_service.dart';
import '../../core/navigation/navigation_intent.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/browser/screens/browser_screen.dart';
import '../../features/downloads/screens/downloads_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/upload/bloc/upload_bloc.dart';

import 'app_drawer.dart';

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
      // Do not clear the intent here, let the screen consume it if needed
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppTheme.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                _AddActionItem(
                  icon: Icons.upload_file_rounded,
                  label: 'Upload File',
                  color: Colors.blue,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUpload();
                  },
                ),
                if (_currentIndex == 1) // Only show in Files tab
                  _AddActionItem(
                    icon: Icons.create_new_folder_rounded,
                    label: 'New Folder',
                    color: AppTheme.warning,
                    onTap: () {
                      Navigator.pop(ctx);
                      // This is a bit tricky since BrowserScreen is inside IndexedStack.
                      // We can use a global notification or event bus, but for now
                      // let's assume we can trigger a re-render or similar.
                      // In a real app, a GlobalKey or a dedicated Bloc event would be better.
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
      bottomNavigationBar: _MobileNavBar(
        currentIndex: _currentIndex,
        onTap: switchTab,
      ),
    );
  }
}

class _AddActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AddActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withAlpha(40),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _MobileNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _MobileNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: 0.5),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NavItem(
                icon: Icons.home_filled,
                label: 'Home',
                selected: currentIndex == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.folder_outlined,
                label: 'Files',
                selected: currentIndex == 1,
                onTap: () => onTap(1),
              ),
              const SizedBox(width: 60), // Space for FAB
              _NavItem(
                icon: Icons.swap_calls_rounded,
                label: 'Transfer',
                selected: currentIndex == 3,
                onTap: () => onTap(3),
              ),
              _NavItem(
                icon: Icons.more_horiz_rounded,
                label: 'More',
                selected: currentIndex == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
          Positioned(
            top: -20,
            child: GestureDetector(
              onTap: () => onTap(2),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: colors.accentPrimary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(50),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.add_rounded,
                  color: isDark ? Colors.black : Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, curve: Curves.easeOut);
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColorsExtension>()!;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? colors.accentPrimary : colors.textTertiary,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? colors.accentPrimary : colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
