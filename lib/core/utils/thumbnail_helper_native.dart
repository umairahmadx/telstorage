import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class ThumbnailHelper {
  static Future<String> prepareVideoSource(Uint8List bytes, String name) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/temp_thumb_$name');
    await tempFile.writeAsBytes(bytes);
    return tempFile.path;
  }

  static void cleanVideoSource(String source) {
    try {
      final file = File(source);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
