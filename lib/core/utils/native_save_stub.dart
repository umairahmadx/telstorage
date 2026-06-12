// Web stub for native_save_helper.dart
import 'dart:typed_data';

class NativeSaveResult {
  final String? savedPath;
  final String message;
  final bool success;
  const NativeSaveResult({
    this.savedPath,
    required this.message,
    required this.success,
  });
}

Future<NativeSaveResult> saveNative(Uint8List bytes, String filename) =>
    throw UnsupportedError('Use web download on web platform');
