import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:telstorage/core/utils/thumbnail_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ThumbnailResult holds bytes and extension', () {
    final result = ThumbnailResult(Uint8List.fromList([1, 2, 3]), 'jpg');
    expect(result.bytes.length, 3);
    expect(result.extension, 'jpg');
  });

  test('ThumbnailGenerator returns null for unsupported mime type', () async {
    final bytes = Uint8List.fromList([0, 0, 0, 0]);
    final result = await ThumbnailGenerator.generate(
      bytes: bytes,
      filename: 'test.unknown',
      mimeType: 'application/unknown',
    );
    expect(result, isNull);
  });
}
