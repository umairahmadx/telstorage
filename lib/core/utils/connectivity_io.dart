/// File: connectivity_io.dart
/// Description: Component and logic definition for connectivity_io.dart in TelStorage.
library;

import 'dart:io';

/// Lightweight connectivity check for native platforms.
class Connectivity {
  static Future<bool> hasConnection() async {
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
