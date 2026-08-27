/*
 * File: error_log_record.dart
 * Description: Data model representing a diagnostic error or warning log entry in TelStorage.
 */

/// Severity level for captured diagnostic logs.
enum ErrorLogLevel {
  /// Fatal crashes or operation failures.
  error,

  /// Recoverable issues or warnings.
  warning,

  /// Diagnostic informational events.
  info,
}

/// Persistent diagnostic log record representing a system, network, or UI error.
class ErrorLogRecord {
  /// Unique event ID.
  final String id;

  /// Timestamp when the error was logged.
  final DateTime timestamp;

  /// Severity level of the log.
  final ErrorLogLevel level;

  /// Subsystem or component tag (e.g. 'TelegramService', 'DownloadQueue', 'FlutterUI').
  final String tag;

  /// High-level description of what occurred.
  final String message;

  /// Detailed error string or exception message.
  final String? errorDetails;

  /// Formatted stack trace if available.
  final String? stackTrace;

  /// Contextual metadata parameters.
  final Map<String, dynamic>? metadata;

  /// Creates an ErrorLogRecord instance.
  const ErrorLogRecord({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.errorDetails,
    this.stackTrace,
    this.metadata,
  });

  /// Converts record to JSON-compatible map for Hive storage.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'level': level.name,
      'tag': tag,
      'message': message,
      'errorDetails': errorDetails,
      'stackTrace': stackTrace,
      'metadata': metadata,
    };
  }

  /// Reconstructs record from dynamic map.
  factory ErrorLogRecord.fromMap(Map<dynamic, dynamic> map) {
    return ErrorLogRecord(
      id: map['id'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      level: ErrorLogLevel.values.firstWhere(
        (e) => e.name == map['level'],
        orElse: () => ErrorLogLevel.error,
      ),
      tag: map['tag'] as String? ?? 'General',
      message: map['message'] as String? ?? '',
      errorDetails: map['errorDetails'] as String?,
      stackTrace: map['stackTrace'] as String?,
      metadata: (map['metadata'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
