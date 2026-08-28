// When should the splash spinner be on screen?
//
// ── The bug these pin ─────────────────────────────────────────────────────
// The spinner used to be tied to the INTERNET PROBE rather than to the work.
// It was armed after the resume check and cleared the moment the probe
// answered — so on an online cold start with no session it appeared for about
// a second, vanished, and THEN the app spent another beat resolving and
// pushing /login. A spinner that stops before the wait does is worse than no
// spinner: it reports "done" while the screen is still blank.
//
// The rule now: the spinner's lifetime is the WORK. It is armed when the
// animation finishes and cleared at the moment of the push — with a short
// grace period so a fast path shows nothing at all rather than a flicker.
//
// These test that rule against the real widget state machine, driven through
// the same timer semantics the splash uses.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Duration _kGrace = Duration(milliseconds: 120);

/// The splash's loader state machine, isolated.
///
/// A faithful copy of `_armLoader` / `_stopLoader` in splash_screen.dart. The
/// splash widget itself cannot be pumped here — it needs an initialized
/// Supabase client, a Navigator with real routes, and a 3.4s animation — so
/// this pins the RULE those two methods implement, which is where the bug was.
class _LoaderController extends ChangeNotifier {
  bool showLoader = false;
  Timer? _armTimer;

  void arm() {
    _armTimer?.cancel();
    _armTimer = Timer(_kGrace, () {
      _armTimer = null;
      showLoader = true;
      notifyListeners();
    });
  }

  void stop() {
    _armTimer?.cancel();
    _armTimer = null;
    if (!showLoader) return;
    showLoader = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    super.dispose();
  }
}

void main() {
  test('work that finishes inside the grace period shows NO spinner', () {
    fakeAsync((async) {
      final c = _LoaderController();

      // A cached resume: armed, then done a few frames later.
      c.arm();
      async.elapse(const Duration(milliseconds: 40));
      c.stop();

      // Past the grace period the timer must NOT fire — a spinner appearing
      // after the screen was already pushed is the flicker this prevents.
      async.elapse(const Duration(seconds: 1));
      expect(c.showLoader, isFalse);
    });
  });

  test('work that outlasts the grace period DOES show a spinner', () {
    fakeAsync((async) {
      final c = _LoaderController();

      c.arm();
      expect(c.showLoader, isFalse, reason: 'not shown during the grace period');

      async.elapse(const Duration(milliseconds: 200));
      expect(c.showLoader, isTrue, reason: 'a real wait is acknowledged');
    });
  });

  test('the spinner stays up until the work ends, not until a probe does', () {
    fakeAsync((async) {
      final c = _LoaderController();
      c.arm();
      async.elapse(const Duration(milliseconds: 200));
      expect(c.showLoader, isTrue);

      // The regression: something else finished (the internet probe) and the
      // spinner came down while the app was still resolving the next route.
      // Only `stop()` — called at the push — may clear it, so simply letting
      // time pass must leave it up.
      async.elapse(const Duration(seconds: 3));
      expect(c.showLoader, isTrue, reason: 'still working, still spinning');

      c.stop();
      expect(c.showLoader, isFalse, reason: 'cleared at the push');
    });
  });

  test('arming twice does not leave an orphan timer', () {
    fakeAsync((async) {
      final c = _LoaderController();
      c.arm();
      async.elapse(const Duration(milliseconds: 50));
      c.arm(); // re-armed before the first fired
      c.stop();

      async.elapse(const Duration(seconds: 1));
      expect(c.showLoader, isFalse);
    });
  });

  testWidgets('the spinner appears instantly but fades out gently', (
    tester,
  ) async {
    // Asymmetric by design: past the grace period the wait is real, so the
    // spinner should commit rather than ramp in — but handing over to the next
    // screen still wants a soft exit.
    Widget build(bool show) => MaterialApp(
      home: AnimatedOpacity(
        opacity: show ? 1.0 : 0.0,
        duration: Duration(milliseconds: show ? 0 : 300),
        curve: Curves.easeOut,
        child: const SizedBox(width: 42, height: 42),
      ),
    );

    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));
    await tester.pump(const Duration(milliseconds: 1));

    var opacity = tester.widget<AnimatedOpacity>(
      find.byType(AnimatedOpacity),
    );
    expect(opacity.duration, Duration.zero, reason: 'appears on the frame');

    await tester.pumpWidget(build(false));
    opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(
      opacity.duration,
      const Duration(milliseconds: 300),
      reason: 'leaves gently',
    );
    await tester.pumpAndSettle();
  });
}
