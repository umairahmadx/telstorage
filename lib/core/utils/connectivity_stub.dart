/*
 * File: connectivity_stub.dart
 * Description: Component and logic definition for connectivity_stub.dart in TelStorage.
 */

class Connectivity {
  static Future<bool> hasConnection() async => true;
}

class OfflineException implements Exception {
  final String message;
  OfflineException(
      [this.message =
          'No internet connection. Please check your network settings.']);

  @override
  String toString() => message;
}
