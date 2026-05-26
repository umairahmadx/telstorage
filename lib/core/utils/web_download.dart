// Web-only file download helper.
// Uses an anchor element with the `download` attribute so the file goes
// straight to the browser's download bar — no OS save dialog.

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Triggers a browser download for [bytes] with the given [filename].
/// The file appears in the browser's download bar immediately — no popup.
void triggerWebDownload(Uint8List bytes, String filename) {
  final blob = html.Blob([bytes]);
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement()
    ..href = url
    ..setAttribute('download', filename)
    ..style.display = 'none';

  html.document.body!.children.add(anchor);
  anchor.click();

  // Cleanup
  html.document.body!.children.remove(anchor);
  html.Url.revokeObjectUrl(url);
}
