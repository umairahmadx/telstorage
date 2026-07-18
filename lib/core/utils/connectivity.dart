export 'connectivity_stub.dart'
    if (dart.library.io) 'connectivity_io.dart'
    if (dart.library.js_interop) 'connectivity_web.dart';
