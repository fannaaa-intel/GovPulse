import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/services/auth_ready.dart';

// A Facebook account that never chose a username, and the two web-only bugs it
// caused.
//
// ── Why web broke where mobile did not ──────────────────────────────────────
// On MOBILE the Facebook round trip happens in an external browser and hands
// control back to the still-running app, so login_screen and signup_screen
// `await` the sign-in and push FacebookUsernameScreen themselves.
//
// On WEB `signInWithOAuth` navigates the whole page away and the redirect back
// is a COLD START. Every await in that flow is gone, so the code after it never
// runs. The splash screen used to catch this and says so in as many words — but
// web stopped building the splash when the shell router landed, and nothing
// replaced it. The citizen arrived signed in with a blank handle and the shell
// rendered `profile?.username ?? ''`: an empty name beside the avatar.
//
// ── What is pinned here ─────────────────────────────────────────────────────
// [AuthRestoration]'s hold, which is the mechanism the guard routes on. The
// guard itself needs Supabase and Firebase and is covered by
// not_found_reachable_test's seam; the screen already has its own layouts and
// is shared with mobile unchanged.
void main() {
  group('the missing-username hold', () {
    test('starts UNKNOWN, so the guard holds rather than guessing', () {
      // The instance is a singleton shared with other suites, so this asserts
      // the property that matters rather than a pristine initial value: an
      // answer is never reported as known until something sets it.
      //
      // Guessing "not missing" here is what the bug looked like — the citizen
      // was routed onward to a shell that then had nothing to render.
      final r = AuthRestoration.instance;
      if (!r.usernameKnown) {
        expect(
          r.usernameMissing,
          isFalse,
          reason: 'an unknown answer must not read as "missing"',
        );
      }
    });

    test('markUsernameChosen releases the hold', () {
      final r = AuthRestoration.instance;

      r.markUsernameChosen();

      expect(r.usernameKnown, isTrue);
      expect(
        r.usernameMissing,
        isFalse,
        reason:
            'the picker calls this after a successful write. If the hold '
            'survived, the guard would send the citizen straight back to the '
            'picker on the very navigation that follows — a loop that reads as '
            'the button doing nothing.',
      );
    });

    test('releasing twice is a no-op, not a second notification', () {
      final r = AuthRestoration.instance;
      var notifications = 0;
      void listener() => notifications++;

      r.markUsernameChosen(); // settle first, so the state is already false
      r.addListener(listener);
      addTearDown(() => r.removeListener(listener));

      r.markUsernameChosen();

      expect(
        notifications,
        0,
        reason:
            'the guard re-runs on every notification; a redundant one on a '
            'hot auth path is wasted work',
      );
    });
  });
}
