// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

class ThumbnailHelper {
  static Future<String> prepareVideoSource(Uint8List bytes, String name) async {
    final blob = html.Blob([bytes]);
    return html.Url.createObjectUrlFromBlob(blob);
  }

  static void cleanVideoSource(String source) {
    try {
      html.Url.revokeObjectUrl(source);
    } catch (_) {}
  }
}
