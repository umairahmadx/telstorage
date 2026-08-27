/*
 * File: error_log_service.dart
 * Description: Centralized diagnostic error and warning logger with Hive persistence, FIFO capping, and export capabilities.
 */

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../constants/app_constants.dart';
import '../models/error_log_record.dart';
import 'hive_service.dart';

/// Central service managing error logs, warnings, and diagnostic records in TelStorage.
class ErrorLogService {
  static ErrorLogService? _instance;

  /// Singleton accessor for ErrorLogService.
  static ErrorLogService get instance => _instance ??= ErrorLogService._();

  Box? _box;
  final ValueNotifier<List<ErrorLogRecord>> _logsNotifier =
      ValueNotifier<List<ErrorLogRecord>>([]);

  /// Notifier exposing the chronological list of logged records.
  ValueNotifier<List<ErrorLogRecord>> get logsNotifier => _logsNotifier;

  /// Maximum number of logs retained before oldest are pruned (FIFO).
  static const int maxLogCapacity = 200;

  ErrorLogService._();

  /// Constructor for dependency injection and testing.
  @visibleForTesting
  ErrorLogService.withBox(Box box) {
    _instance = this;
    _box = box;
    _loadLogs();
  }

  /// Resets instance for testing purposes.
  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  /// Initializes the service and opens its Hive persistence box defensively.
  Future<void> init() async {
    _box = await HiveService.openBoxDefensively(AppConstants.errorLogsBox);
    _loadLogs();
  }

  void _loadLogs() {
    if (_box == null || !_box!.isOpen) return;
    final records = <ErrorLogRecord>[];
    for (final raw in _box!.values) {
      if (raw is Map) {
        try {
          records.add(ErrorLogRecord.fromMap(raw));
        } catch (e) {
          debugPrint('ErrorLogService: failed to parse log entry: $e');
        }
      }
    }
    records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _logsNotifier.value = records;
  }

  /// Records an error event with optional details, stack trace, and metadata.
  Future<void> logError(
    String message, {
    String? tag,
    Object? error,
    dynamic stackTrace,
    Map<String, dynamic>? metadata,
  }) async {

    await _addRecord(
      ErrorLogRecord(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        level: ErrorLogLevel.error,
        tag: tag ?? 'General',
        message: message,
        errorDetails: error?.toString(),
        stackTrace: stackTrace?.toString(),
        metadata: metadata,
      ),
    );
  }

  /// Records a warning event.
  Future<void> logWarning(
    String message, {
    String? tag,
    Object? error,
  }) async {
    await _addRecord(
      ErrorLogRecord(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        level: ErrorLogLevel.warning,
        tag: tag ?? 'General',
        message: message,
        errorDetails: error?.toString(),
      ),
    );
  }

  /// Records an informational diagnostic event.
  Future<void> logInfo(
    String message, {
    String? tag,
  }) async {
    await _addRecord(
      ErrorLogRecord(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        level: ErrorLogLevel.info,
        tag: tag ?? 'General',
        message: message,
      ),
    );
  }

  Future<void> _addRecord(ErrorLogRecord record) async {
    final updated = List<ErrorLogRecord>.from(_logsNotifier.value)..add(record);
    while (updated.length > maxLogCapacity) {
      updated.removeAt(0);
    }
    _logsNotifier.value = updated;

    if (_box != null && _box!.isOpen) {
      try {
        await _box!.add(record.toMap());
        while (_box!.length > maxLogCapacity) {
          await _box!.deleteAt(0);
        }
      } catch (e) {
        debugPrint('ErrorLogService: failed to persist error record: $e');
      }
    }
  }

  /// Clears all stored error logs from memory and disk.
  Future<void> clearLogs() async {
    _logsNotifier.value = [];
    if (_box != null && _box!.isOpen) {
      try {
        await _box!.clear();
      } catch (e) {
        debugPrint('ErrorLogService: failed to clear box: $e');
      }
    }
  }

  /// Generates a plain-text diagnostic report suitable for exporting/sharing.
  String exportDiagnosticReport() {
    final buffer = StringBuffer();
    final nowFormatted =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    buffer.writeln('========================================');
    buffer.writeln('TelStorage Diagnostic Report');
    buffer.writeln('Generated: $nowFormatted');
    buffer.writeln('Platform: ${kIsWeb ? "Web" : Platform.operatingSystem}');
    buffer.writeln('Total Logged Events: ${_logsNotifier.value.length}');
    buffer.writeln('========================================\n');

    if (_logsNotifier.value.isEmpty) {
      buffer.writeln('No errors or warnings recorded.');
      return buffer.toString();
    }

    for (final log in _logsNotifier.value) {
      final time = DateFormat('HH:mm:ss.SSS').format(log.timestamp);
      buffer.writeln(
          '[$time] [${log.level.name.toUpperCase()}] [${log.tag}] ${log.message}');
      if (log.errorDetails != null && log.errorDetails!.isNotEmpty) {
        buffer.writeln('  Details: ${log.errorDetails}');
      }
      if (log.metadata != null && log.metadata!.isNotEmpty) {
        buffer.writeln('  Metadata: ${log.metadata}');
      }
      if (log.stackTrace != null && log.stackTrace!.isNotEmpty) {
        buffer.writeln('  StackTrace:');
        buffer.writeln(
            log.stackTrace!.split('\n').map((l) => '    $l').join('\n'));
      }
      buffer.writeln('----------------------------------------');
    }

    return buffer.toString();
  }
}
