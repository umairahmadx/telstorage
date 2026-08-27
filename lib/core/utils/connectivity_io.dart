/*
 * File: connectivity_io.dart
 * Description: Lightweight connectivity check for native platforms with test mock override.
 */

import 'dart:io';
import 'package:flutter/foundation.dart';

/// Lightweight connectivity check for native platforms.
class Connectivity {
  /// Test override hook for deterministic connectivity simulation.
  @visibleForTesting
  static bool? mockConnectionStatus;

  static Future<bool> hasConnection() async {
    if (mockConnectionStatus != null) {
      return mockConnectionStatus!;
    }
    try {
      final result = await InternetAddress.lookup('google.com').timeout(
        const Duration(seconds: 3),
      );
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
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
