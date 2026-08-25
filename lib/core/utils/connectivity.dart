/*
 * File: connectivity.dart
 * Description: Component and logic definition for connectivity.dart in TelStorage.
 */

export 'connectivity_stub.dart'
    if (dart.library.io) 'connectivity_io.dart'
    if (dart.library.js_interop) 'connectivity_web.dart';
