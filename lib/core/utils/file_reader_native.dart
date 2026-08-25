/*
 * File: file_reader_native.dart
 * Description: Component and logic definition for file_reader_native.dart in TelStorage.
 */

// Native (Android/iOS/Desktop) file reader.
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();
