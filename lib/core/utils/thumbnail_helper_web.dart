import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart';

class ThumbnailHelper {
  static Future<String> prepareVideoSource(Uint8List bytes, String name) async {
    final blob = Blob([bytes.toJS].toJS);
    return URL.createObjectURL(blob);
  }

  static void cleanVideoSource(String source) {
    try {
      URL.revokeObjectURL(source);
    } catch (_) {}
  }
}
