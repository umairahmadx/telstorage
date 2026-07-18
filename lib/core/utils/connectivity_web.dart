import 'package:web/web.dart' as web;

/// Browser connectivity is advisory: the actual request still determines
/// whether the current network can reach the service.
class Connectivity {
  static Future<bool> hasConnection() async => web.window.navigator.onLine;
}

class OfflineException implements Exception {
  final String message;
  OfflineException(
      [this.message =
          'No internet connection. Please check your network settings.']);

  @override
  String toString() => message;
}
