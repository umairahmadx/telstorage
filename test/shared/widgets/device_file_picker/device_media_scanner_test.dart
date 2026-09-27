/*
 * File: device_media_scanner_test.dart
 * Description: Unit tests for DeviceMediaScanner album loading and zero-copy path resolution.
 */

import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/shared/widgets/device_file_picker/device_media_scanner.dart';

void main() {
  group('DeviceMediaScanner', () {
    test('MediaAlbum model stores name and count', () {
      const album = MediaAlbum(
        id: 'test-id',
        name: 'Camera',
        mediaCount: 42,
        pathEntity: null,
      );

      expect(album.name, 'Camera');
      expect(album.mediaCount, 42);
      expect(album.id, 'test-id');
    });

    test('resolveUploadPath constructs direct POSIX path on Android', () {
      const relativePath = 'DCIM/Camera/';
      const title = 'IMG_2026.jpg';
      const expectedPath = '/storage/emulated/0/$relativePath$title';

      final constructedPath = DeviceMediaScanner.constructDirectPath(
        relativePath: relativePath,
        title: title,
      );
      expect(constructedPath, expectedPath);
    });

    test('resolveUploadPath marks iOS paths as temporary', () {
      final result = DeviceMediaScanner.isTemporaryPath(
        '/var/mobile/Containers/Data/Application/cache/IMG.jpg',
      );
      expect(result, isTrue);

      final result2 = DeviceMediaScanner.isTemporaryPath(
        '/storage/emulated/0/DCIM/Camera/IMG.jpg',
      );
      expect(result2, isFalse);
    });
  });
}
