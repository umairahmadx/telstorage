/*
 * File: connectivity_stub.dart
 * Description: Connectivity stub definition with test mock override.
 */

class Connectivity {
  /// Test override hook for deterministic connectivity simulation.
  static bool? mockConnectionStatus;

  static Future<bool> hasConnection() async {
    if (mockConnectionStatus != null) {
      return mockConnectionStatus!;
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
