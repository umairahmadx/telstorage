/*
 * File: error_log_record_test.dart
 * Description: Unit tests for ErrorLogRecord serialization and deserialization.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/models/error_log_record.dart';

void main() {
  group('ErrorLogRecord', () {
    test('serializes and deserializes correctly via Map', () {
      final now = DateTime.now();
      final record = ErrorLogRecord(
        id: 'test-123',
        timestamp: now,
        level: ErrorLogLevel.error,
        tag: 'TelegramService',
        message: 'Flood wait error 429',
        errorDetails: 'TimeoutException after 30s',
        stackTrace: '#0 TelegramService.downloadChunk',
        metadata: {'chunkIndex': 2},
      );

      final map = record.toMap();
      final reconstructed = ErrorLogRecord.fromMap(map);

      expect(reconstructed.id, equals('test-123'));
      expect(reconstructed.timestamp.millisecondsSinceEpoch,
          equals(now.millisecondsSinceEpoch));
      expect(reconstructed.level, equals(ErrorLogLevel.error));
      expect(reconstructed.tag, equals('TelegramService'));
      expect(reconstructed.message, equals('Flood wait error 429'));
      expect(reconstructed.errorDetails, equals('TimeoutException after 30s'));
      expect(
          reconstructed.stackTrace, equals('#0 TelegramService.downloadChunk'));
      expect(reconstructed.metadata?['chunkIndex'], equals(2));
    });

    test('handles null optional fields and missing keys gracefully', () {
      final emptyMap = <dynamic, dynamic>{
        'id': 'fallback-id',
        'message': 'Simple info message',
        'level': 'info',
      };
      final reconstructed = ErrorLogRecord.fromMap(emptyMap);

      expect(reconstructed.id, equals('fallback-id'));
      expect(reconstructed.message, equals('Simple info message'));
      expect(reconstructed.level, equals(ErrorLogLevel.info));
      expect(reconstructed.tag, equals('General'));
      expect(reconstructed.errorDetails, isNull);
      expect(reconstructed.stackTrace, isNull);
      expect(reconstructed.metadata, isNull);
    });
  });
}
