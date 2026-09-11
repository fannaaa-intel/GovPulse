import 'dart:js_interop';

/// The function defined by `#splash-screen-script` in `web/index.html`.
///
/// Declared as an external binding rather than reached through a dynamic
/// `callMethod`, so a rename in index.html surfaces here instead of failing
/// silently at runtime and leaving the splash up forever.
@JS('removeSplashFromWeb')
external void _removeSplashFromWeb();

@JS('removeSplashFromWeb')
external JSAny? get _removeSplashFromWebRef;

/// Dismisses the HTML first-paint splash.
///
/// Guarded on the binding actually existing: a host serving an older or
/// customised index.html (or a test harness with a bare page) has no such
/// function, and a missing-function throw during startup would take the whole
/// app down over what is only a cosmetic teardown.
void removeWebSplash() {
  try {
    if (_removeSplashFromWebRef == null) return;
    _removeSplashFromWeb();
  } catch (_) {
    // Never let the splash teardown break boot; worst case the fade is skipped.
  }
}
