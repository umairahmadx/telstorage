// Web stub — FilePicker always returns bytes on web, so this is never called.
import 'dart:typed_data';

Future<Uint8List> readFileBytes(String path) => throw UnsupportedError(
  'File path reading not supported on web. Use bytes from FilePicker.',
);
