/// Dismisses the HTML first-paint splash painted by `web/index.html`.
///
/// WEB ONLY IN EFFECT. The conditional export below hands the mobile build a
/// no-op stub, so nothing about the Android/iOS startup path changes — the
/// native app has its own Flutter-side splash (`features/onboarding`) and no
/// HTML shell at all.
///
/// Why this exists: Flutter web paints nothing until its engine has downloaded
/// and booted. index.html therefore paints a plain-CSS splash on the browser's
/// first pass, and something has to take it down once the real first frame is
/// up. That teardown function shipped in index.html from the start but had no
/// caller, so the splash markup was removed instead — which is why the page
/// was blank white during boot rather than branded.
library;

export 'web_splash_stub.dart'
    if (dart.library.js_interop) 'web_splash_web.dart';
