import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central place for all app-wide constants.
class AppConstants {
  AppConstants._();

  // Google Apps Script URL — loaded dynamically from .env
  static String get scriptUrl => dotenv.env['SCRIPT_URL'] ?? 'https://script.google.com/macros/s/AKfycbyB4GIeRwFR8DQGPqLCuNDbDShSdWttVH7Blf8t2F1FM8BR1WPuouGVQW6CJgZa314x/exec';

  // Telegram Bot API base URL — token is injected at runtime
  static const String telegramApiBase = 'https://api.telegram.org/bot';
  static const String telegramFileBase = 'https://api.telegram.org/file/bot';

  // Hive box names
  static const String filesBox = 'files';
  static const String foldersBox = 'folders';
  static const String downloadsBox = 'downloads';

  // Telegram limits
  /// Maximum file size Telegram Bot API allows per upload (50 MB)
  static const int maxUploadBytes = 50 * 1024 * 1024;
  
  /// Telegram Bot API: getFile can only serve files ≤ 20 MB.
  /// We use 19 MB per part to stay safely under this limit.
  static const int chunkSizeBytes = 19922944; // 19 MB

  // Rate limiting
  static const int uploadDelayMs = 500;

  // Storage
  static const double defaultStorageLimitMb = 10240.0; // 10 GB
}
