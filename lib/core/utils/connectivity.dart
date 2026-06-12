import 'dart:io';
import 'package:flutter/foundation.dart';

/// Lightweight check for internet connectivity.
class Connectivity {
  /// Returns true if the device can resolve a public domain, false otherwise.
  static Future<bool> hasConnection() async {
    if (kIsWeb) {
      // In web, check navigator.onLine (stubbed as true if unavailable)
      return true; 
    }
    try {
      final result = await InternetAddress.lookup('google.com').timeout(
        const Duration(seconds: 3),
      );
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}

/// Custom exception thrown when offline
class OfflineException implements Exception {
  final String message;
  OfflineException([this.message = 'No internet connection. Please check your network settings.']);

  @override
  String toString() => message;
}
