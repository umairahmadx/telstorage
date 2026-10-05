/*
 * File: connectivity_web.dart
 * Description: Browser connectivity adapter with test mock override.
 */

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// Browser connectivity is advisory: the actual request still determines
/// whether the current network can reach the service.
class Connectivity {
  /// Test override hook for deterministic connectivity simulation.
  @visibleForTesting
  static bool? mockConnectionStatus;

  /// Test override hook for deterministic unmetered-network simulation.
  @visibleForTesting
  static bool? mockUnmeteredStatus;

  static Future<bool> hasConnection() async {
    if (mockConnectionStatus != null) {
      return mockConnectionStatus!;
    }
    return web.window.navigator.onLine;
  }

  /// Web builds are conservative: metered state is unknown, so report metered.
  static Future<bool> isUnmetered() async {
    if (mockUnmeteredStatus != null) {
      return mockUnmeteredStatus!;
    }
    return false;
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
