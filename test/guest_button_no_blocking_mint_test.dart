// "Continue as guest" must never wait on the network before it navigates.
//
// ── The bug ────────────────────────────────────────────────────────────────
// The login screen's guest callback did:
//
//     await FirebaseAuth.instance.signInAnonymously();   // no timeout
//     goToGuest(ctx);
//
// `signInAnonymously` is a live round trip with NO timeout of its own. On a
// device that cannot reach Firebase it neither returns nor throws — it hangs.
// `goToGuest` was therefore never reached, and because nothing threw, the
// try/catch added for the error case never fired either. The result on a real
// phone was a button that did nothing at all, forever, with no message.
//
// The SIGN-UP screen's guest button navigates synchronously and always worked.
// That asymmetry is the whole diagnosis: the difference between the two
// buttons was the await, not the wiring.
//
// The mint exists only to satisfy the WEB auth guard, which classifies a guest
// by `FirebaseAuth.currentUser.isAnonymous`. Mobile has no such guard, so the
// phone has nothing to wait on and must navigate immediately.
//
// These model the two callback shapes rather than pumping the router: the real
// callback needs a live Firebase, and the test binding cannot provide a hang
// that is distinguishable from a pass any other way.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Stands in for `signInAnonymously()` when the network is unreachable: a
/// future that never completes, which is exactly what the device saw.
Future<void> _neverCompletes() => Completer<void>().future;

/// The OLD shape — await the mint, then navigate.
Future<void> _oldCallback({
  required Future<void> Function() mint,
  required void Function() navigate,
  required void Function(Object) onError,
}) async {
  try {
    await mint();
  } catch (e) {
    onError(e);
    return;
  }
  navigate();
}

/// The NEW shape on mobile — navigate first, never touch the mint.
Future<void> _mobileCallback({
  required Future<void> Function() mint,
  required void Function() navigate,
}) async {
  navigate();
}

/// The NEW shape on web — still awaits, but bounded so it cannot hang.
Future<void> _webCallback({
  required Future<void> Function() mint,
  required void Function() navigate,
  required void Function(Object) onError,
  Duration limit = const Duration(seconds: 10),
}) async {
  try {
    await mint().timeout(limit);
  } catch (e) {
    onError(e);
    return;
  }
  navigate();
}

void main() {
  group('the old callback is why the button looked dead', () {
    test('an unreachable Firebase means it NEVER navigates or errors', () {
      var navigated = false;
      var errored = false;

      // Deliberately not awaited: awaiting it here would hang the test the
      // same way it hung the button.
      unawaited(
        _oldCallback(
          mint: _neverCompletes,
          navigate: () => navigated = true,
          onError: (_) => errored = true,
        ),
      );

      return Future<void>.delayed(const Duration(milliseconds: 50), () {
        expect(navigated, isFalse, reason: 'the tap went nowhere');
        expect(
          errored,
          isFalse,
          reason: 'and nothing threw, so no message was ever shown — '
              'which is why the catch alone did not fix this',
        );
      });
    });

    test('it DOES navigate when the network is healthy', () async {
      // Proving the old code was not broken for everyone: it worked whenever
      // the mint happened to resolve, which is why it passed in testing.
      var navigated = false;
      await _oldCallback(
        mint: () async {},
        navigate: () => navigated = true,
        onError: (_) {},
      );
      expect(navigated, isTrue);
    });
  });

  group('mobile navigates regardless of the network', () {
    test('an unreachable Firebase does not stop it', () async {
      var navigated = false;
      var minted = false;

      await _mobileCallback(
        mint: () async {
          minted = true;
          return _neverCompletes();
        },
        navigate: () => navigated = true,
      );

      expect(navigated, isTrue, reason: 'the guest screen opens immediately');
      expect(minted, isFalse, reason: 'the mint is not even started on mobile');
    });

    test('it is synchronous, like the sign-up button that always worked', () {
      var navigated = false;
      // No await anywhere: navigate() must already have run by the time the
      // call returns its future.
      _mobileCallback(mint: _neverCompletes, navigate: () => navigated = true);
      expect(navigated, isTrue);
    });
  });

  group('web still mints, but cannot hang', () {
    test('a hanging mint ends as an error instead of never returning', () async {
      var navigated = false;
      Object? seen;

      await _webCallback(
        mint: _neverCompletes,
        navigate: () => navigated = true,
        onError: (e) => seen = e,
        limit: const Duration(milliseconds: 50),
      );

      expect(seen, isA<TimeoutException>());
      expect(navigated, isFalse, reason: 'the guard needs the user on web');
    });

    test('a healthy mint navigates as before', () async {
      var navigated = false;
      await _webCallback(
        mint: () async {},
        navigate: () => navigated = true,
        onError: (_) {},
        limit: const Duration(milliseconds: 50),
      );
      expect(navigated, isTrue);
    });
  });
}
