/// File: local_file_native.dart
/// Description: Component and logic definition for local_file_native.dart in TelStorage.
library;

import 'dart:io';

Future<bool> deleteLocalFileIfExists(String path) async {
  final file = File(path);
  if (!await file.exists()) return false;
  await file.delete();
  return true;
}
