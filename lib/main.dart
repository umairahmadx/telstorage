import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/models/file_record.dart';
import 'core/models/folder_record.dart';

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
  await Hive.openBox<FileRecord>(AppConstants.filesBox);
  await Hive.openBox<FolderRecord>(AppConstants.foldersBox);

  runApp(const TelStorageApp());
}
