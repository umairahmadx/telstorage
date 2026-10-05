/*
 * File: connectivity_stub.dart
 * Description: Connectivity stub definition with test mock override.
 */


class Connectivity {
  /// Test override hook for deterministic connectivity simulation.
  static bool? mockConnectionStatus;

  /// Test override hook for deterministic unmetered-network simulation.
  static bool? mockUnmeteredStatus;

  static Future<bool> hasConnection() async {
    if (mockConnectionStatus != null) {
      return mockConnectionStatus!;
    }
    return true;
  }

  /// Unmetered check for the default conditional-export branch.
  ///
  /// The stub mirrors [hasConnection] and stays optimistic. This branch is
  /// what the Dart analyzer resolves for static analysis; io and web builds
  /// select their own variants at compile time.
  static Future<bool> isUnmetered() async {
    if (mockUnmeteredStatus != null) {
      return mockUnmeteredStatus!;
    }
    return true;
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