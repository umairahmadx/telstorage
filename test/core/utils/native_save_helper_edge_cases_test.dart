/*
 * File: native_save_helper_edge_cases_test.dart
 * Description: Edge case tests for native save helper path sanitization, traversal defense, and fallback resolution.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/utils/native_save_helper.dart';

void main() {
  group('NativeSaveHelper Edge Cases & Path Sanitization', () {
    test('EC-06: resolveSafeSubpath strips path traversal sequences (..)', () {
      expect(
        resolveSafeSubpath('../../Secret/Invoices', 'doc.pdf'),
        equals('Secret/Invoices'),
      );
      expect(
        resolveSafeSubpath('..//..//Data', 'doc.pdf'),
        equals('Data'),
      );
      expect(
        resolveSafeSubpath('..', 'doc.pdf'),
        equals('documents'), // falls back to extension category
      );
    });

    test('EC-07: resolveSafeFilename sanitizes illegal characters and delimiters', () {
      expect(
        resolveSafeFilename('report:draft*2026?.pdf'),
        equals('report_draft_2026.pdf'),
      );
      expect(
        resolveSafeFilename('evil/../file.exe'),
        equals('evil_file.exe'),
      );
      expect(
        resolveSafeFilename('   '),
        equals('unnamed_file'),
      );
    });

    test('EC-07: resolveSafeSubpath sanitizes forbidden OS characters', () {
      expect(
        resolveSafeSubpath('Work:Folder*2026?|', 'doc.pdf'),
        equals('Work_Folder_2026'),
      );
    });

    test('EC-10: saveNative saves safely in test environment without throwing', () async {
      final sampleData = Uint8List.fromList([10, 20, 30, 40]);
      final result = await saveNative(
        sampleData,
        'test:invoice*1.pdf',
        subpath: '../../TestFolder/Invoices',
      );

      expect(result.success, isTrue);
      expect(result.savedPath, isNotNull);
      expect(result.savedPath, isNot(contains('..')));
      expect(result.savedPath, contains('TestFolder'));

      if (result.savedPath != null) {
        final file = File(result.savedPath!);
        expect(file.existsSync(), isTrue);
        expect(file.lengthSync(), equals(4));
        await file.delete();
      }
    });
  });
}
