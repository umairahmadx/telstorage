// Web fallback. The incoming-share platform plugin is mobile-only.

Future<bool> incomingShareFileExists(String path) async => false;

Future<int> incomingShareFileSize(String path) async => 0;

Future<void> deleteIncomingShareFile(String path) async {}
