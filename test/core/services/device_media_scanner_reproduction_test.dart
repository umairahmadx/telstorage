/*
 * File: device_media_scanner_reproduction_test.dart
 * Description: Automated reproduction test verifying path normalization and
 * originFile/file fallback behavior in DeviceMediaScanner.
 */

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:telstorage/core/services/device_media_scanner.dart';

class _FakeAssetEntity extends Fake implements AssetEntity {
  @override
  final String id;
  @override
  final String? title;
  @override
  final String? relativePath;
  final File? _file;
  final bool originThrows;

  _FakeAssetEntity({
    required this.id,
    this.title,
    this.relativePath,
    File? file,
    this.originThrows = false,
  }) : _file = file;

  @override
  Future<File?> get originFile async {
    if (originThrows) throw Exception('originFile permission restricted');
    return null;
  }

  @override
  Future<File?> get file async => _file;
}

void main() {
  group('DeviceMediaScanner Reproduction Tests', () {
    test('constructDirectPath normalizes missing trailing slash in relativePath', () {
      // If relativePath lacks a trailing slash (e.g. 'DCIM/Camera'),
      // constructDirectPath must insert the separator so that the filename is
      // not glued directly onto the album name ('DCIM/CameraIMG_0001.jpg').
      final path = DeviceMediaScanner.constructDirectPath(
        relativePath: 'DCIM/Camera',
        title: 'IMG_0001.jpg',
      );

      // In current code, this produces '/storage/emulated/0/DCIM/CameraIMG_0001.jpg'
      expect(
        path,
        '/storage/emulated/0/DCIM/Camera/IMG_0001.jpg',
        reason: 'Path must normalize missing trailing slash between folder and title',
      );
    });

    test('constructDirectPath normalizes duplicate leading slashes', () {
      // If relativePath has a leading slash (e.g. '/DCIM/Camera/'),
      // constructDirectPath must avoid double slashes ('/storage/emulated/0//DCIM/Camera/').
      final path = DeviceMediaScanner.constructDirectPath(
        relativePath: '/DCIM/Camera/',
        title: 'IMG_0001.jpg',
      );

      // In current code, this produces '/storage/emulated/0//DCIM/Camera/IMG_0001.jpg'
      expect(
        path,
        '/storage/emulated/0/DCIM/Camera/IMG_0001.jpg',
        reason: 'Path must normalize leading slash',
      );
    });

    test('resolveUploadPath must fall back to asset.file when originFile is unavailable',
        () async {
      final tempFile = File('${Directory.systemTemp.path}/test_asset_file.jpg');
      await tempFile.writeAsBytes([1, 2, 3, 4]);

      final asset = _FakeAssetEntity(
        id: 'asset_fallback_test_1',
        title: 'test_asset_file.jpg',
        relativePath: 'DCIM/Camera/',
        file: tempFile,
        originThrows: true,
      );

      try {
        // In current code, resolveUploadPath only checks asset.originFile and
        // immediately throws StateError without ever attempting asset.file!
        final result = await DeviceMediaScanner.resolveUploadPath(asset);

        expect(result.$1, tempFile.path);
        expect(result.$2, isTrue,
            reason: 'Fallback to asset.file should be marked as temporary');
      } finally {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
    });
  });
}
