import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The boot ring must not change size mid-handoff.
//
// ── The bug ─────────────────────────────────────────────────────────────────
// A cold web load shows the ring twice in a row, from two different
// implementations:
//
//   1. `#splash-ring` in web/index.html — plain CSS, painted before Flutter
//      exists, so something is on screen during the ~1s of engine boot;
//   2. `_StartingUp` in citizen_shell_router.dart — the Flutter ring, held
//      while the auth guard decides where the visitor belongs.
//
// They are meant to be the same ring, and the code said so — "the same one
// web/index.html restates in CSS". The numbers disagreed: 84 in CSS, 72 in
// Dart. So the handoff visibly SHRANK the ring and the next screen restored it.
// After a Facebook redirect, where both halves are on screen in sequence, it
// read as the spinner pulsing.
//
// ── Why a test rather than a comment ────────────────────────────────────────
// The two values live in different LANGUAGES, in different files, and neither
// compiler can see the other. Nothing but a test can hold them together, which
// is exactly how they drifted apart in the first place — a comment claiming
// they matched sat directly above the value that did not.
//
// This reads both files as text on purpose. Importing the Dart constant would
// only prove Dart agrees with itself.
void main() {
  /// Pulls `width: NNpx;` out of the `#splash-ring` rule.
  int cssRingSize() {
    final html = File('web/index.html').readAsStringSync();
    final rule = RegExp(
      r'#splash-ring\s*\{[^}]*?width:\s*(\d+)px',
      dotAll: true,
    ).firstMatch(html);
    expect(
      rule,
      isNotNull,
      reason:
          'web/index.html no longer has a #splash-ring rule with an explicit '
          'width. If the splash was redesigned, update this test to match — do '
          'not delete it, or the two rings can drift apart again.',
    );
    return int.parse(rule!.group(1)!);
  }

  /// Pulls the `size:` out of `_StartingUp`'s BrandSpinner.
  int dartRingSize() {
    final dart = File(
      'lib/features/home/shell/citizen_shell_router.dart',
    ).readAsStringSync();
    final match = RegExp(
      r'BrandSpinner\(size:\s*(\d+),\s*onDark:\s*false\)',
    ).firstMatch(dart);
    expect(
      match,
      isNotNull,
      reason:
          '_StartingUp no longer builds a BrandSpinner in the expected shape. '
          'Update the pattern rather than dropping the check.',
    );
    return int.parse(match!.group(1)!);
  }

  test('the HTML splash ring and the Flutter ring are the same size', () {
    final css = cssRingSize();
    final dart = dartRingSize();

    expect(
      dart,
      css,
      reason:
          'A cold load paints the CSS ring, then the Flutter ring, then the '
          'app. Different sizes make the ring jump mid-boot — it was 84 in CSS '
          'and 72 in Dart, which read as the spinner shrinking and then growing '
          'again. Whichever one changes, the other has to follow.',
    );
  });

  test('the ring is BrandSpinner default size', () {
    // 84 is BrandSpinner's own default and what the sign-out overlay uses, so
    // it is the value the other two should track rather than a number chosen
    // here. Pinned so a change to the default is a deliberate, visible edit in
    // three places instead of a silent mismatch in one.
    expect(
      dartRingSize(),
      84,
      reason:
          'BrandSpinner defaults to 84 and logout_confirm_dialog uses 84. If '
          'that default moves, move this and #splash-ring with it.',
    );
  });
}
