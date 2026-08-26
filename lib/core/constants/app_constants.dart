/*
 * File: app_constants.dart
 * Description: Master central repository for all application constants, API endpoints, storage keys, limits, and action types.
 */

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central catalog of all app-wide configuration tokens, keys, and constants.
class AppConstants {
  AppConstants._();

  // ── Environment & API Endpoints ──────────────────────────────────────────

  /// Google Apps Script URL — loaded dynamically from .env.
  static String get scriptUrl => dotenv.env['SCRIPT_URL'] ?? '';

  /// Telegram Bot API base URL — token is injected at runtime.
  static const String telegramApiBase = 'https://api.telegram.org/bot';

  /// Telegram File API base URL — token is injected at runtime.
  static const String telegramFileBase = 'https://api.telegram.org/file/bot';

  /// Pinned master metadata JSON filename on Telegram channel.
  static const String metadataFileName = '.metadata.json';

  /// Prefix for partitioned folder metadata files.
  static const String partitionPrefix = 'partition_';

  /// Partition identifier representing root level files.
  static const String rootFolderPartitionId = 'root';

  /// Sentinel string denoting root directory placement.
  static const String rootFolderSentinelId = '__root__';

  // ── Hive Box Names ───────────────────────────────────────────────────────

  /// Hive box storing cached file records.
  static const String filesBox = 'files';

  /// Hive box storing cached folder records.
  static const String foldersBox = 'folders';

  /// Hive box storing persistent download jobs.
  static const String downloadsBox = 'downloads';

  /// Hive box storing optimistic offline-first pending sync actions.
  static const String pendingActionsBox = 'pending_actions';

  /// Hive box storing active web share links.
  static const String webSharesBox = 'web_shares';

  /// Hive box storing partially uploaded chunk states for instant resume.
  static const String uploadChunksBox = 'upload_chunks';

  // ── Secure Storage Keys ──────────────────────────────────────────────────

  /// FlutterSecureStorage key for the Telegram bot token.
  static const String keyBotToken = 'bot_token';

  /// FlutterSecureStorage key for the Telegram target channel ID.
  static const String keyChannelId = 'channel_id';

  /// FlutterSecureStorage key for authenticated user email.
  static const String keyEmail = 'email';

  /// FlutterSecureStorage key for pinned metadata Telegram message ID.
  static const String keyMetadataMessageId = 'metadata_message_id';

  /// FlutterSecureStorage key for pinned metadata Telegram permanent file ID.
  static const String keyMetadataFileId = 'metadata_file_id';

  // ── Offline Sync Pending Action Types ────────────────────────────────────

  /// Action type for creating a folder.
  static const String actionCreateFolder = 'createFolder';

  /// Action type for renaming a folder.
  static const String actionRenameFolder = 'renameFolder';

  /// Action type for deleting a folder tree.
  static const String actionDeleteFolder = 'deleteFolder';

  /// Action type for moving a folder.
  static const String actionMoveFolder = 'moveFolder';

  /// Action type for copying a folder.
  static const String actionCopyFolder = 'copyFolder';

  /// Action type for renaming a file.
  static const String actionRenameFile = 'renameFile';

  /// Action type for moving a file.
  static const String actionMoveFile = 'moveFile';

  /// Action type for copying a file.
  static const String actionCopyFile = 'copyFile';

  /// Action type for deleting a file.
  static const String actionDeleteFile = 'deleteFile';

  /// Action type for syncing metadata after file upload.
  static const String actionAddFileMeta = 'addFileMeta';

  // ── File Transfer & Storage Limits ───────────────────────────────────────

  /// Maximum file size Telegram Bot API allows per upload (50 MB).
  static const int maxUploadBytes = 50 * 1024 * 1024;

  /// Telegram Bot API: getFile can only serve files <= 20 MB.
  /// We use 19 MB per chunk to stay safely under this limit (19,922,944 bytes).
  static const int chunkSizeBytes = 19922944;

  /// Maximum number of recent files displayed on Home screen.
  static const int maxRecentFilesCount = 20;

  /// In-memory LRU folder partition cache maximum capacity.
  static const int lruFolderCacheCapacity = 30;

  // ── Thumbnail Generator Specifications ───────────────────────────────────

  /// Maximum pixel width/height dimension for generated thumbnails (400px).
  static const int thumbnailMaxDimension = 400;

  /// Default compression quality percentage for thumbnail JPEG/WebP generation (80%).
  static const int thumbnailQuality = 80;

  /// Strict 50 KB ceiling limit for thumbnail file byte size (51,200 bytes).
  static const int thumbnailMaxByteSize = 50 * 1024;

  // ── Delays & Timers ──────────────────────────────────────────────────────

  /// Delay between sequential chunk uploads in milliseconds.
  static const int uploadDelayMs = 500;

  /// Debounce time in milliseconds before processing pending sync actions.
  static const int syncDebounceMs = 300;

  /// Background periodic sync interval in seconds.
  static const int syncIntervalSeconds = 30;

  /// Fast UI transition animation duration (200ms).
  static const Duration animDurationFast = Duration(milliseconds: 200);

  /// Standard UI transition animation duration (300ms).
  static const Duration animDurationMedium = Duration(milliseconds: 300);

  // ── Category Filter Identifiers ──────────────────────────────────────────

  /// Images category filter key.
  static const String categoryImages = 'image';

  /// Videos category filter key.
  static const String categoryVideos = 'video';

  /// Documents category filter key.
  static const String categoryDocuments = 'document';

  /// Audio category filter key.
  static const String categoryAudio = 'audio';

  /// Compressed archives category filter key.
  static const String categoryArchives = 'archive';
}
