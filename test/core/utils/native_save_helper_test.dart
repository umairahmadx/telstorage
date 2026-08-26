/*
 * File: native_save_helper_test.dart
 * Description: Unit tests verifying subpath directory preservation during native save operations.
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/utils/native_save_helper.dart';

void main() {
  test('TC-01: saveNative creates nested subfolders when subpath is specified', () async {
    final sampleData = Uint8List.fromList([1, 2, 3, 4, 5]);
    final result = await saveNative(
      sampleData,
      'nested_test_file.txt',
      subpath: 'Work/Invoices',
    );
    expect(result.success, isTrue);
    expect(result.savedPath, isNotNull);
    expect(result.savedPath!, contains('Invoices'));

    final file = File(result.savedPath!);
    expect(file.existsSync(), isTrue);
    await file.delete();
  });

  test('TC-02: saveNative falls back to extension subfolder when subpath is null', () async {
    final sampleData = Uint8List.fromList([1, 2, 3]);
    final result = await saveNative(
      sampleData,
      'sample_photo.jpg',
    );
    expect(result.success, isTrue);
    expect(result.savedPath, isNotNull);
    expect(result.savedPath!, contains('photo'));

    final file = File(result.savedPath!);
    if (file.existsSync()) {
      await file.delete();
    }
  });
}
