/*
 * File: telegram_dio_adapter_helper.dart
 * Description: Conditional adapter configuration for Dio across native and web platforms.
 */

export 'telegram_dio_adapter_stub.dart'
    if (dart.library.io) 'telegram_dio_adapter_native.dart'
    if (dart.library.js_interop) 'telegram_dio_adapter_web.dart';
