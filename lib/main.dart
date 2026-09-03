/*
 * File: main.dart
 * Description: Entry point for TelStorage initializing WorkManager, Hive boxes, adapters, and environment variables.
 */

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/models/download_job.dart';
import 'core/models/file_record.dart';
import 'core/models/folder_record.dart';
import 'core/models/pending_action.dart';
import 'core/services/error_log_service.dart';
import 'core/services/hive_service.dart';
import 'core/services/theme_service.dart';


/// Top-level callback dispatcher for Workmanager background sync execution.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint("WorkManager: background sync task triggered: $task");

      // Re-initialize Hive in the background isolate
      await Hive.initFlutter();
      if (!Hive.isAdapterRegistered(0)) {
        Hive.registerAdapter(FileRecordAdapter());
      }
      if (!Hive.isAdapterRegistered(1)) {
        Hive.registerAdapter(FolderRecordAdapter());
      }
      if (!Hive.isAdapterRegistered(2)) {
        Hive.registerAdapter(DownloadJobAdapter());
      }
      if (!Hive.isAdapterRegistered(3)) {
        Hive.registerAdapter(PendingActionAdapter());
      }

      final pendingBox =
          await Hive.openBox<PendingAction>(AppConstants.pendingActionsBox);

      if (pendingBox.isEmpty) {
        debugPrint("WorkManager: no pending actions — skipping sync.");
        await Hive.close();
        return true;
      }

      // Note: Full queue processing requires active Telegram network services,
      // which are managed in the main isolate by SyncQueueService on launch and
      // periodic 30s timers. This background isolate task verifies queue persistence.
      debugPrint(
          "WorkManager: ${pendingBox.length} pending action(s) detected in local queue. "
          "Queue processing is dispatched by SyncQueueService on app start/resume.");

      await Hive.close();
      return true;
    } catch (e) {
      debugPrint("WorkManager: background task failed: $e");
      return false;
    }
  });
}

/// Main application entry point initializing core bindings and persistence.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize WorkManager
  try {
    Workmanager().initialize(
      callbackDispatcher,
    );
  } catch (e) {
    debugPrint("Workmanager init warning: $e");
  }

  // Load environment variables from .env
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: Could not load .env file: $e");
  }

  // Initialize Hive local database
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(FileRecordAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(FolderRecordAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(DownloadJobAdapter());
  if (!Hive.isAdapterRegistered(3)) {
    Hive.registerAdapter(PendingActionAdapter());
  }
  await HiveService.openBoxDefensively<FileRecord>(AppConstants.filesBox);
  await HiveService.openBoxDefensively<FolderRecord>(AppConstants.foldersBox);
  await HiveService.openBoxDefensively<DownloadJob>(AppConstants.downloadsBox);
  await HiveService.openBoxDefensively<PendingAction>(
    AppConstants.pendingActionsBox,
    preserveQuarantine: true,
  );
  await HiveService.openBoxDefensively(AppConstants.webSharesBox);
  await HiveService.openBoxDefensively(AppConstants.uploadChunksBox);


  // Initialize ErrorLogService & Hive Box
  await ErrorLogService.instance.init();


  // Setup Global Error Handlers to record uncaught crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    ErrorLogService.instance.logError(
      details.exceptionAsString(),
      tag: 'FlutterUI',
      error: details.exception,
      stackTrace: details.stack,
      metadata: {'library': details.library},
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    ErrorLogService.instance.logError(
      error.toString(),
      tag: 'UncaughtAsync',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  // Initialize Theme Service
  await ThemeService.instance.init();

  runApp(const TelStorageApp());
}

