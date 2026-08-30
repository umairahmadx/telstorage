/*
 * File: file_reader_native.dart
 * Description: Component and logic definition for file_reader_native.dart in TelStorage.
 */

// Native (Android/iOS/Desktop) file reader.
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readFileBytes(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw PathNotFoundException(
        path, const OSError('File does not exist or was removed', 2));
  }
  return await file.readAsBytes();
}

Future<void> deleteFileIfExists(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}
