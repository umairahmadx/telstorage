/*
 * File: connectivity_web.dart
 * Description: Browser connectivity adapter with test mock override.
 */

import 'package:web/web.dart' as web;

/// Browser connectivity is advisory: the actual request still determines
/// whether the current network can reach the service.
class Connectivity {
  /// Test override hook for deterministic connectivity simulation.
  static bool? mockConnectionStatus;

  static Future<bool> hasConnection() async {
    if (mockConnectionStatus != null) {
      return mockConnectionStatus!;
    }
    return web.window.navigator.onLine;
  }
}

class OfflineException implements Exception {
  final String message;
  OfflineException(
      [this.message =
          'No internet connection. Please check your network settings.']);

  @override
  String toString() => message;
}
