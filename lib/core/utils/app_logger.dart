/*
 * File: app_logger.dart
 * Description: Component and logic definition for app_logger.dart in TelStorage.
 */

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../services/error_log_service.dart';

/// Centralized app logger. Use [AppLogger.d/i/w/e] throughout the codebase.
/// In release builds, only warnings and errors are printed.
/// Errors and warnings are automatically recorded to [ErrorLogService].
class AppLogger {
  AppLogger._();

  static final _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 100,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.none,
    ),
    level: kReleaseMode ? Level.warning : Level.debug,
    filter: ProductionFilter(),
  );

  static void d(String message, {String? tag}) =>
      _logger.d(tag != null ? '[$tag] $message' : message);

  static void i(String message, {String? tag}) {
    _logger.i(tag != null ? '[$tag] $message' : message);
    if (tag != null) {
      ErrorLogService.instance.logInfo(message, tag: tag);
    }
  }

  static void w(String message, {String? tag, Object? error}) {
    _logger.w(tag != null ? '[$tag] $message' : message, error: error);
    ErrorLogService.instance.logWarning(message, tag: tag, error: error);
  }

  static void e(String message,
      {String? tag, Object? error, StackTrace? stackTrace}) {
    _logger.e(tag != null ? '[$tag] $message' : message,
        error: error, stackTrace: stackTrace);
    ErrorLogService.instance.logError(message,
        tag: tag, error: error, stackTrace: stackTrace);
  }
}

