import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/models/file_record.dart';
import 'core/models/folder_record.dart';
import 'core/models/download_job.dart';
import 'core/models/pending_action.dart';
import 'core/services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: Could not load .env file: $e");
  }

  // Initialize Hive local database
  await Hive.initFlutter();
  Hive.registerAdapter(FileRecordAdapter());
  Hive.registerAdapter(FolderRecordAdapter());
  Hive.registerAdapter(DownloadJobAdapter());
  Hive.registerAdapter(PendingActionAdapter());
  await Hive.openBox<FileRecord>(AppConstants.filesBox);
  await Hive.openBox<FolderRecord>(AppConstants.foldersBox);
  await Hive.openBox<DownloadJob>(AppConstants.downloadsBox);
  await Hive.openBox<PendingAction>(AppConstants.pendingActionsBox);
  await Hive.openBox(AppConstants.webSharesBox);

  // Initialize Theme Service
  await ThemeService.instance.init();

  runApp(const TelStorageApp());
}
