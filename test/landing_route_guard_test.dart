import 'package:flutter_test/flutter_test.dart';

// ════════════════════════════════════════════════════════════════════════════
//  The landing page's guard decision, isolated.
//
//  ── Why this mirrors the logic instead of importing it ─────────────────────
//  The real `_authRedirect` in citizen_shell_router.dart reads
//  `Supabase.instance.client.auth.currentSession`, `FirebaseAuth.instance` and
//  the `AuthRestoration` singleton. None of those can be stood up in a widget
//  test without initialising both SDKs, and the branch under test does not care
//  about any of them beyond three plain facts: has restoration settled, is
//  there a session, and is the role known.
//
//  So the landing branch is restated here over those three inputs, exactly as
//  the router expresses it, and the tests pin the BEHAVIOUR. This is the same
//  approach shell_deep_link_test.dart already takes with the route tree.
//
//  ── What is actually at risk ───────────────────────────────────────────────
//  The one-shot latch. Making '/' public is trivial; making it public WITHOUT
//  dumping every returning citizen onto marketing copy on every refresh is the
//  part with a real failure mode, and it is invisible in a code review because
//  both cases are the same URL. These tests are here to make a regression in
//  that sequencing loud.
// ════════════════════════════════════════════════════════════════════════════

/// Mirrors the landing branch of `_authRedirect`, over explicit inputs.
///
/// Kept deliberately in the same ORDER and with the same early returns as the
/// original, so a reader can set them side by side.
class _LandingGuard {
  bool handoffDone = false;

  /// Returns the redirect target, or null to serve the landing page.
  String? evaluate({
    required bool settled,
    required bool hasSession,
    required bool roleKnown,
    required int? roleId,
  }) {
    if (handoffDone) return null;
    if (!settled) return null;

    handoffDone = true;

    if (hasSession) {
      if (!roleKnown) {
        handoffDone = false;
        return null;
      }
      return switch (roleId) {
        1 => '/admin',
        2 => '/staff',
        _ => '/home',
      };
    }
    return null;
  }
}

void main() {
  group('boot-time arrival at /', () {
    test('a signed-out visitor is served the landing page', () {
      final guard = _LandingGuard();
      final target = guard.evaluate(
        settled: true,
        hasSession: false,
        roleKnown: true,
        roleId: null,
      );
      expect(target, isNull, reason: 'a stranger at / must see the page');
    });

    test('a returning citizen is handed to their feed', () {
      final guard = _LandingGuard();
      expect(
        guard.evaluate(
          settled: true,
          hasSession: true,
          roleKnown: true,
          roleId: null,
        ),
        '/home',
      );
    });

    test('a returning admin is handed to their console, not the feed', () {
      final guard = _LandingGuard();
      expect(
        guard.evaluate(
          settled: true,
          hasSession: true,
          roleKnown: true,
          roleId: 1,
        ),
        '/admin',
      );
    });

    test('a returning staff member is handed to the staff console', () {
      final guard = _LandingGuard();
      expect(
        guard.evaluate(
          settled: true,
          hasSession: true,
          roleKnown: true,
          roleId: 2,
        ),
        '/staff',
      );
    });
  });

  group('holds', () {
    test('an unsettled pass holds WITHOUT spending the handoff', () {
      final guard = _LandingGuard();

      // The boot sequence: the guard runs before restoration has reported.
      expect(
        guard.evaluate(
          settled: false,
          hasSession: false,
          roleKnown: false,
          roleId: null,
        ),
        isNull,
      );
      expect(
        guard.handoffDone,
        isFalse,
        reason: 'a hold must not consume the one-shot handoff',
      );

      // Restoration lands, and NOW the citizen is recognised and sent home.
      expect(
        guard.evaluate(
          settled: true,
          hasSession: true,
          roleKnown: true,
          roleId: null,
        ),
        '/home',
        reason: 'the handoff must survive the unsettled pass to fire here',
      );
    });

    test('a session with an unknown role holds and un-spends the latch', () {
      final guard = _LandingGuard();

      expect(
        guard.evaluate(
          settled: true,
          hasSession: true,
          roleKnown: false,
          roleId: null,
        ),
        isNull,
        reason: 'guessing a role would sweep an admin to the citizen feed',
      );
      expect(
        guard.handoffDone,
        isFalse,
        reason: 'the pass could not decide, so it must not claim the handoff',
      );

      // The role query lands: the admin reaches their console.
      expect(
        guard.evaluate(
          settled: true,
          hasSession: true,
          roleKnown: true,
          roleId: 1,
        ),
        '/admin',
      );
    });
  });

  group('after the handoff — deliberate visits', () {
    test('a citizen who navigates BACK to / gets the landing page', () {
      final guard = _LandingGuard();

      // Boot: handed to the feed.
      expect(
        guard.evaluate(
          settled: true,
          hasSession: true,
          roleKnown: true,
          roleId: null,
        ),
        '/home',
      );

      // Later, they click the logo. Same inputs, same URL — different answer,
      // because the handoff is spent. This is the whole point of the latch.
      expect(
        guard.evaluate(
          settled: true,
          hasSession: true,
          roleKnown: true,
          roleId: null,
        ),
        isNull,
        reason: 'the landing page must be reachable from inside the app',
      );
    });

    test('an admin can open the landing page to review it', () {
      final guard = _LandingGuard();

      expect(
        guard.evaluate(
          settled: true,
          hasSession: true,
          roleKnown: true,
          roleId: 1,
        ),
        '/admin',
      );
      expect(
        guard.evaluate(
          settled: true,
          hasSession: true,
          roleKnown: true,
          roleId: 1,
        ),
        isNull,
        reason: 'LGU staff must be able to look at their own front page',
      );
    });

    test('a signed-out visitor who leaves and returns is not redirected', () {
      final guard = _LandingGuard();

      // Boot on the landing page — this spends the handoff.
      expect(
        guard.evaluate(
          settled: true,
          hasSession: false,
          roleKnown: true,
          roleId: null,
        ),
        isNull,
      );
      expect(guard.handoffDone, isTrue);

      // They visit /login, decide against it, and come back.
      expect(
        guard.evaluate(
          settled: true,
          hasSession: false,
          roleKnown: true,
          roleId: null,
        ),
        isNull,
      );
    });
  });
}
