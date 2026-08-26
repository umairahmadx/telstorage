/*
 * File: native_save_stub.dart
 * Description: Component and logic definition for native_save_stub.dart in TelStorage.
 */

// Web stub for native_save_helper.dart
import 'dart:typed_data';

class NativeSaveResult {
  final String? savedPath;
  final String message;
  final bool success;
  const NativeSaveResult(
      {this.savedPath, required this.message, required this.success});
}

Future<NativeSaveResult> saveNative(
  Uint8List bytes,
  String filename, {
  String? subpath,
}) =>
    throw UnsupportedError('Use web download on web platform');
