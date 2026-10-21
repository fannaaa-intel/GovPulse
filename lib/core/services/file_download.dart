/// Saves a file the server has already prepared, from a browser tab.
///
/// Web-only. Every entry point is guarded by `kIsWeb`; the non-web build gets
/// the stub, which throws, because on Android and iOS the share sheet /
/// `url_launcher` path is the one that must run.
library;

export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
