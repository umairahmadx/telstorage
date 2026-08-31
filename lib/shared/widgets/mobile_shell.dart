/*
 * File: mobile_shell.dart
 * Description: Bottom navigation shell container hosting persistent tab views (Home, Files, Upload, Downloads, Settings).
 */

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/utils/app_logger.dart';
import '../../core/utils/battery_optimization_helper.dart';
import '../../core/utils/file_opener_helper.dart';
import '../../core/utils/storage_permission_helper.dart';
import 'package:uuid/uuid.dart';

import '../../core/navigation/navigation_intent.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/service_locator.dart';
import '../../core/services/transfer_queue_service.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../features/browser/presentation/screens/browser/browser_screen.dart';
import '../../features/browser/presentation/screens/browser/viewmodel/browser_view_model.dart';
import '../../features/downloads/presentation/screens/downloads/downloads_screen.dart';
import '../../features/home/presentation/screens/home/home_screen.dart';
import '../../features/settings/presentation/screens/settings/settings_screen.dart';
import '../../features/upload/presentation/viewmodels/upload_folder_helper.dart';
import '../../features/upload/presentation/viewmodels/upload_view_model.dart';
import 'app_drawer.dart';
import 'mobile_shell/mobile_add_action_item.dart';
import 'mobile_shell/mobile_bottom_nav.dart';

/// Shell component providing unified navigation scaffold with drawer and bottom bar.
class MobileShell extends StatefulWidget {
  /// Initial tab index to open.
  final int initialIndex;

  /// Constructs MobileShell.
  const MobileShell({super.key, this.initialIndex = 0});

  /// Accessor to find MobileShellState in context tree.
  static MobileShellState? of(BuildContext context) {
    return context.findAncestorStateOfType<MobileShellState>();
  }

  @override
  State<MobileShell> createState() => MobileShellState();
}

/// State controller for MobileShell managing active tab and deep-linked transfer notifications.
class MobileShellState extends State<MobileShell> {
  /// Currently active bottom tab index.
  late int _currentIndex;

  /// Scaffold key for opening navigation drawer.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    ServiceLocator.instance.navigation.intentNotifier
        .addListener(_onIntentChanged);
    NotificationService.instance.onNotificationTap = handleNotificationResponse;

    // Check if app was opened directly from a notification tap
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final launchResponse =
          await NotificationService.instance.getAppLaunchNotificationDetails();
      if (launchResponse != null && mounted) {
        handleNotificationResponse(launchResponse);
      }
    });
  }

  @override
  void dispose() {
    ServiceLocator.instance.navigation.intentNotifier
        .removeListener(_onIntentChanged);
    super.dispose();
  }

  /// Synchronizes active tab with navigation intent changes.
  void _onIntentChanged() {
    final intent = ServiceLocator.instance.navigation.intentNotifier.value;
    if (intent != null) {
      setState(() {
        _currentIndex = intent.shellIndex;
      });
    }
  }

  /// Handles incoming push notification actions and payload taps.
  void handleNotificationResponse(NotificationResponse details) {
    final payload = details.payload;
    final actionId = details.actionId;

    AppLogger.i('Notification response: actionId=$actionId, payload=$payload',
        tag: 'MobileShell');

    if (actionId != null && actionId.isNotEmpty) {
      if (actionId.startsWith('pause_')) {
        final id = actionId.replaceFirst('pause_', '');
        TransferQueueService.instance.pauseTask(id);
        return;
      } else if (actionId.startsWith('resume_')) {
        final id = actionId.replaceFirst('resume_', '');
        TransferQueueService.instance.resumeTask(id);
        return;
      } else if (actionId.startsWith('cancel_')) {
        final id = actionId.replaceFirst('cancel_', '');
        TransferQueueService.instance.cancelTask(id);
        return;
      } else if (actionId.startsWith('open_path:')) {
        final filePath = actionId.replaceFirst('open_path:', '');
        FileOpenerHelper.openFile(
          context,
          filePath: filePath,
        );
        return;
      } else if (actionId.startsWith('open_')) {
        final id = actionId.replaceFirst('open_', '');
        final job = ServiceLocator.instance.downloadQueue.allJobs
            .where((j) => j.fileId == id)
            .firstOrNull;
        final path = job?.localPath ??
            ServiceLocator.instance.downloadQueue.getCompletedPath(id);
        if (path != null) {
          FileOpenerHelper.openFile(
            context,
            filePath: path,
            mimeType: job?.mimeType,
            fileName: job?.name,
          );
        } else {
          ServiceLocator.instance.navigation
              .navigateTo(AppDestination.transferDownloads);
        }
        return;
      } else if (actionId.startsWith('copy_url:')) {
        final url = actionId.replaceFirst('copy_url:', '');
        _copyAndFeedback(url);
        return;
      } else if (actionId.startsWith('copy_')) {
        final id = actionId.replaceFirst('copy_', '');
        final share = ServiceLocator.instance.webShareQueue.allShares
            .where((s) => s.fileId == id)
            .firstOrNull;
        if (share?.shareUrl != null) {
          _copyAndFeedback(share!.shareUrl!);
        }
        return;
      } else if (actionId == 'view_all') {
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferActive);
        return;
      } else if (actionId == 'view_uploads') {
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferUploads);
        return;
      } else if (actionId == 'view_downloads') {
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferDownloads);
        return;
      } else if (actionId == 'view_shared') {
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferShared);
        return;
      }
    }

    if (payload == 'transfer_active') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferActive);
    } else if (payload == 'transfer_upload') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferUploads);
    } else if (payload == 'transfer_download') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferDownloads);
    } else if (payload == 'transfer_share') {
      ServiceLocator.instance.navigation
          .navigateTo(AppDestination.transferShared);
    }
  }

  void _copyAndFeedback(String url) {
    Clipboard.setData(ClipboardData(text: url));
    HapticFeedback.lightImpact();
    if (mounted) {
      final colors = Theme.of(context).extension<AppColorsExtension>()!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: colors.success, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Share link copied: $url',
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Opens the side navigation drawer.
  void openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  /// Switches active tab.
  void switchTab(int index) {
    if (index == _currentIndex || index < 0 || index > 4) return;
    if (index == 2) {
      _showAddMenu();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _currentIndex = index);
  }

  /// Getter for current tab index.
  int get currentIndex => _currentIndex;

  /// Shows floating add/upload modal action bottom sheet.
  void _showAddMenu() {
    HapticFeedback.mediumImpact();
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
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                AddActionItem(
                  icon: AppIcons.uploadFile,
                  label: 'Upload Files',
                  color: AppTheme.primary,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(ctx);
                    _pickAndUpload();
                  },
                ),
                AddActionItem(
                  icon: Icons.drive_folder_upload_rounded,
                  label: 'Upload Folder',
                  color: AppTheme.primaryLight,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(ctx);
                    _pickAndUploadFolder();
                  },
                ),
                if (_currentIndex == 1)
                  AddActionItem(
                    icon: AppIcons.newFolder,
                    label: 'New Folder',
                    color: AppTheme.warning,
                    onTap: () {
                      HapticFeedback.selectionClick();
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

  /// Opens directory picker and enqueues folder files with hierarchy for upload.
  Future<void> _pickAndUploadFolder() async {
    final hasPermission =
        await StoragePermissionHelper.ensureStoragePermission(context);
    if (!hasPermission || !mounted) return;

    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null || dirPath.isEmpty) return;

    if (!mounted) return;

    try {
      final browserState = context.read<BrowserBloc>().state;
      final currentFolderId =
          _currentIndex == 1 ? browserState.currentFolderId : null;

      final scanResult = await UploadFolderHelper.scanAndQueueFolder(
        dirPath: dirPath,
        targetParentFolderId: currentFolderId,
        storageRepository: ServiceLocator.instance.storageRepository,
        uploadBloc: context.read<UploadBloc>(),
      );

      if (scanResult.filesCount > 0 && mounted) {
        await BatteryOptimizationHelper.maybePromptBatteryOptimization(context);
        if (!mounted) return;
        ServiceLocator.instance.navigation
            .navigateTo(AppDestination.transferUploads);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The selected folder contains no files to upload.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FolderInaccessibleException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
            backgroundColor:
                Theme.of(context).extension<AppColorsExtension>()?.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to read folder: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor:
                Theme.of(context).extension<AppColorsExtension>()?.error,
          ),
        );
      }
    }
  }

  /// Shows dialog for creating a new folder in browser view.
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
          style:
              TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
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
            child:
                Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accentPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
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

  /// Opens file picker and enqueues selected files for upload.
  Future<void> _pickAndUpload() async {
    final picked = await FilePicker.platform
        .pickFiles(withData: kIsWeb, allowMultiple: true);
    if (picked == null || picked.files.isEmpty) return;

    final browserState = context.read<BrowserBloc>().state;
    final currentFolderId =
        _currentIndex == 1 ? browserState.currentFolderId : null;

    final List<UploadTask> tasks = [];
    const uuid = Uuid();
    for (final file in picked.files) {
      if (!kIsWeb && (file.path == null || file.path!.isEmpty)) continue;
      if (kIsWeb && file.bytes == null) continue;
      tasks.add(UploadTask(
        id: uuid.v4(),
        path: file.path,
        bytes: file.bytes,
        name: file.name,
        size: file.size,
        folderId: currentFolderId,
        isTemporaryCacheFile: !kIsWeb,
      ));
    }

    if (tasks.isNotEmpty && mounted) {
      await BatteryOptimizationHelper.maybePromptBatteryOptimization(context);
      if (!mounted) return;
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
