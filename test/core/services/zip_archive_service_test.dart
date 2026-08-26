/*
 * File: zip_archive_service_test.dart
 * Description: Unit tests for ZipArchiveService verifying zip compression and archive entry preservation.
 */

import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/services/zip_archive_service.dart';

void main() {
  test('TC-01: createZipFromFiles creates valid zip archive with nested entry paths', () async {
    final tempDir = await Directory.systemTemp.createTemp('zip_unit_test_');
    final file1 = File('${tempDir.path}/hello.txt')..writeAsStringSync('Hello World');
    final nestedDir = Directory('${tempDir.path}/nested')..createSync();
    final file2 = File('${nestedDir.path}/doc.pdf')..writeAsStringSync('%PDF-1.4 dummy content');

    final zipDestination = File('${tempDir.path}/output.zip');

    await ZipArchiveService.createZipFromFiles(
      destinationZip: zipDestination,
      entries: [
        ZipEntry(file: file1, archivePath: 'hello.txt'),
        ZipEntry(file: file2, archivePath: 'nested/doc.pdf'),
      ],
    );

    expect(zipDestination.existsSync(), isTrue);
    expect(zipDestination.lengthSync(), greaterThan(0));

    // Verify zip archive contents using ZipDecoder
    final bytes = zipDestination.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final fileNames = archive.files.map((f) => f.name).toList();

    expect(fileNames, contains('hello.txt'));
    expect(fileNames, contains('nested/doc.pdf'));

    await tempDir.delete(recursive: true);
  });
}
