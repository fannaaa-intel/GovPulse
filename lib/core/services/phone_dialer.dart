/// Places a phone call from a browser tab.
///
/// Web-only. Every entry point is guarded by `kIsWeb`; the non-web build gets
/// the stub, which throws, because on Android and iOS the native path
/// (`AndroidIntent` / `url_launcher`) is the one that must run.
library;

export 'phone_dialer_stub.dart'
    if (dart.library.js_interop) 'phone_dialer_web.dart';
