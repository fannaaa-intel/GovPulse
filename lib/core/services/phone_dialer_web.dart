import 'package:web/web.dart' as web;

/// Hands `number` to the browser's dialer.
///
/// ── Why this does not go through url_launcher ──────────────────────────────
/// `url_launcher_web` reaches every URL — `tel:` included — through
/// `window.open(url, target, 'noopener,noreferrer')`. On Chrome that is fine.
/// Safari runs `window.open` past its popup blocker, which lets it through
/// only while the page still holds the user gesture that asked for it, and
/// even then treats a programmatic open of a non-http scheme as a popup. The
/// result on iOS and iPadOS was a slider that animated to the end and dialled
/// nothing.
///
/// A synthesised click on an `<a href="tel:…">` is a *navigation*, not a popup,
/// so the blocker never looks at it. `_top` is there for the case where the app
/// is framed: Safari refuses an external-scheme navigation from inside a
/// subframe, and targeting the top frame is what the url_launcher plugin
/// itself does for `tel:` (flutter/flutter#51461). Outside a frame `_top` is
/// just the current tab.
///
/// ── This must be called synchronously from a user gesture ──────────────────
/// Safari grants the permission to navigate away for the duration of the event
/// handler and takes it back as soon as the stack unwinds. An `await` before
/// this call is enough to lose it; a `Future.delayed` is far too late. Callers
/// dial first and animate afterwards, never the other way round.
void dialFromBrowser(String number) {
  final anchor = web.HTMLAnchorElement()
    ..href = 'tel:$number'
    ..target = '_top';
  anchor.style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
}

/// Whether the browser is running on a device with a real touch screen.
///
/// This exists for iPadOS. Safari there requests desktop sites by default, so
/// `defaultTargetPlatform` reports macOS and the window is 820–1366 px wide —
/// an iPad was indistinguishable from an iMac, and the emergency screen hid
/// its dial affordance from a device that dials perfectly well.
///
/// `maxTouchPoints` is the one signal that separates them: an iPad reports 5,
/// a Mac reports 0. A touch-screen Windows laptop also reports a positive
/// number and will be offered a dialer it may not have — the same harmless
/// false positive the width heuristic already accepted, and the number stays
/// printed on screen beside the copy button either way.
bool browserReportsTouchDevice() => web.window.navigator.maxTouchPoints > 1;
