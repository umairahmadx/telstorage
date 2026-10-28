import 'dart:io';

Future<bool> incomingShareFileExists(String path) => File(path).exists();

Future<int> incomingShareFileSize(String path) => File(path).length();

Future<void> deleteIncomingShareFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}
