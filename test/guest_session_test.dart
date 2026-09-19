// Pins the MOBILE half of the guest anonymous-session contract.
//
// The bug this file accompanies was web-only: a visitor who reached /guest from
// the sign-up screen, the landing hero or the 404 page had no anonymous Firebase
// user minted for them, so tapping "Continue as Guest" ran the router's auth
// guard while `currentUser` was still null. The guard reads that as SIGNED OUT
// and sweeps to /login — the visitor asked for the feed and got the login
// screen. A second attempt then "worked", because the unawaited mint started by
// GuestScreen.initState had landed in the meantime.
//
// The fix makes [goToGuestFeed] await [ensureGuestAnonSession] before it
// navigates. That is a WEB path — `kIsWeb` is a compile-time false under the VM,
// so the mint, the de-duplication and the guard are all unreachable from here
// and are verified in a browser instead (see the session notes on
// tool/preview_* targets and CDP).
//
// What IS reachable, and what these cases exist for, is the other half of the
// contract: that none of it costs mobile anything. Mobile has no guard — its
// feed carries `isGuest` as a route argument — so it must never mint, never
// wait, and never behave differently because the web path grew an await. Both
// functions short-circuit on `!kIsWeb` before touching FirebaseAuth, which is
// exactly why these run with no Firebase binding initialised at all: if either
// ever reached the plugin off web, these tests would throw instead of pass.
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/services/guest_session.dart';

void main() {
  group('off web, the guest session is inert', () {
    test('reports no session without touching FirebaseAuth', () {
      // `hasGuestAnonSession` reads FirebaseAuth.instance on web. Off web it
      // must answer from `kIsWeb` alone — reaching the plugin here would throw,
      // because no Firebase binding is initialised in this test.
      expect(hasGuestAnonSession, isFalse);
    });

    test('minting is a no-op that completes', () async {
      // The call mobile inherits from the shared helper. It must return
      // immediately and it must not create anything.
      await ensureGuestAnonSession();
      expect(hasGuestAnonSession, isFalse);
    });

    test('repeated calls stay a no-op', () async {
      // The in-flight de-duplication added for web must not introduce any
      // state that survives off web — every call takes the same early return.
      for (var i = 0; i < 5; i++) {
        await ensureGuestAnonSession();
      }
      expect(hasGuestAnonSession, isFalse);
    });

    test('concurrent calls all complete without a Firebase binding', () async {
      // The shape the fix actually creates on web: GuestScreen.initState starts
      // a mint and goToGuestFeed awaits one a moment later. Off web both must
      // resolve immediately rather than sharing a future that never completes.
      await Future.wait([
        ensureGuestAnonSession(),
        ensureGuestAnonSession(),
        ensureGuestAnonSession(),
      ]);
      expect(hasGuestAnonSession, isFalse);
    });
  });
}
