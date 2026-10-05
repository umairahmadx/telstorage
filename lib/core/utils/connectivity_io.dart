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

  /// Test override hook for deterministic unmetered-network simulation.
  @visibleForTesting
  static bool? mockUnmeteredStatus;

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

  /// Whether the active network is unmetered (Wi-Fi/Ethernet).
  ///
  /// Uses interface names as a heuristic: `wlan*`/`eth*` count as unmetered,
  /// cellular (`rmnet*`, `ccmni*`, `pdp*`) and VPN (`tun*`) do not. This is a
  /// best-effort check — tethered hotspots and VPN-over-Wi-Fi may be
  /// misclassified, so callers must treat a `true` result as advisory.
  static Future<bool> isUnmetered() async {
    if (mockUnmeteredStatus != null) {
      return mockUnmeteredStatus!;
    }
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        final isWifi = name.startsWith('wlan') || name.startsWith('wl');
        final isEthernet =
            name.startsWith('eth') || name.startsWith('en');
        if ((isWifi || isEthernet) && interface.addresses.isNotEmpty) {
          return true;
        }
      }
      return false;
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
