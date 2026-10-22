import 'package:web/web.dart' as web;

/// Navigates the browser to [url] so it saves the file as [filename].
///
/// ── Why this does not go through url_launcher ──────────────────────────────
/// `url_launcher_web` opens every URL with
/// `window.open(url, target, 'noopener,noreferrer')`. Safari runs that past its
/// popup blocker and allows it only while the page still holds the user gesture
/// that asked for it — the same trap that made the emergency dialer animate to
/// the end and dial nothing (see `phone_dialer_web.dart`).
///
/// A synthesised click on an `<a download>` is a *navigation*, not a popup, so
/// the blocker never looks at it, and the `download` attribute is what makes
/// the browser save the bytes instead of trying to display them.
///
/// ── This must be called synchronously from a user gesture ──────────────────
/// Safari grants permission to navigate away for the duration of the event
/// handler and takes it back as the stack unwinds. An `await` before this call
/// is enough to lose it.
///
/// That is exactly why the backup page fetches the signed URL on one tap and
/// then shows a separate **Download file** button: the `await` for the URL and
/// the navigation that uses it cannot live in the same gesture, so they are
/// split into two taps rather than hoping the blocker is lenient.
///
/// `download` also only takes effect for a same-origin URL *or* one served with
/// `Content-Disposition: attachment`. Supabase signed URLs created with the
/// `download` option send that header, so the filename is honoured and a
/// cross-origin link still saves rather than navigating the app away.
void downloadFromBrowser(String url, String filename) {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    // Not `_top`: unlike `tel:`, this is an ordinary https navigation that the
    // download attribute turns into a save, and keeping it in the current
    // browsing context avoids replacing the console if a browser ever ignores
    // the attribute.
    ..rel = 'noopener';
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
}
