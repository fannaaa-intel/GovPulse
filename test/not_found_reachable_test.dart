import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/home/shell/citizen_shell_router.dart';

// Does an unmatched URL actually REACH the 404 page?
//
// ── Why this is not obvious ─────────────────────────────────────────────────
// `errorBuilder` only runs for a location that fails to match a route AND is
// not redirected away first. GoRouter runs `redirect` BEFORE it decides a
// location is an error, so a top-level guard that sweeps unknown paths makes
// the error builder unreachable — the page is built, wired, tested and looks
// perfect, and no visitor ever sees it.
//
// [citizenRouter]'s guard is closed-by-default in every branch, on purpose:
//
//   _signedOutRedirect  allowlists /login, /signup, /guest    → else /login
//   _guestRedirect      allowlists those plus /newsfeed       → else /login
//   _citizenRedirect    sweeps the public pages               → else null
//   _consoleRedirect    allowlists the console subtree        → else console
//
// Three of those four send an unknown path somewhere real, which means a
// mistyped URL lands on login or the feed rather than on the 404.
//
// These tests pin the ROUTING DECISION for an unmatched path, so the answer is
// recorded rather than assumed. They are about reachability only — the page's
// own layout is covered by not_found_page_responsive_test.dart.
void main() {
  group('an unmatched location reaches the error builder', () {
    test('the redirect exposes what it does with an unknown path', () {
      // debugRedirectFor is the seam added for this test: it runs the same
      // decision the router runs, without needing a pumped app, a Supabase
      // client or a Firebase user.
      //
      // null  = "use the requested location" → the error builder runs → 404.
      // a path = swept there → the 404 is unreachable for that visitor.
      expect(
        debugRedirectFor('/my-reprots', identity: RouterIdentity.signedOut),
        isNull,
        reason:
            'A signed-out visitor who mistypes a URL must land on the 404, '
            'not be swept to /login. A sweep here makes the 404 unreachable '
            'for the visitor most likely to hit one — the stranger following '
            'a shared link that rotted.',
      );
    });

    test('a guest with an unknown path also reaches the 404', () {
      expect(
        debugRedirectFor('/evets', identity: RouterIdentity.guest),
        isNull,
        reason: 'A guest mistyping a URL should see the 404, not /login.',
      );
    });

    test('a signed-in citizen with an unknown path reaches the 404', () {
      expect(
        debugRedirectFor('/my-reprots', identity: RouterIdentity.citizen),
        isNull,
        reason:
            'A citizen following a dead in-app link should see the 404, not '
            'be silently bounced to their feed with no explanation.',
      );
    });
  });

  group('the guard still sweeps what it is supposed to', () {
    // The fix must not open the door it exists to close. A 404 that works by
    // letting anyone reach any route would be much worse than no 404.
    test('a signed-out visitor is still sent away from a protected page', () {
      expect(
        debugRedirectFor('/settings', identity: RouterIdentity.signedOut),
        '/login',
      );
      expect(
        debugRedirectFor('/my-reports', identity: RouterIdentity.signedOut),
        '/login',
      );
    });

    test('a guest is still sent away from a citizen-only page', () {
      expect(
        debugRedirectFor('/settings', identity: RouterIdentity.guest),
        '/login',
      );
    });

    test('the public pages stay public', () {
      expect(
        debugRedirectFor('/login', identity: RouterIdentity.signedOut),
        isNull,
      );
      expect(
        debugRedirectFor('/guest', identity: RouterIdentity.signedOut),
        isNull,
      );
      expect(
        debugRedirectFor('/scan/abc123', identity: RouterIdentity.signedOut),
        isNull,
      );
    });
  });
}
