// Which nav chrome a viewport gets. Worth pinning independently of any widget:
// this rule decides whether a citizen sees the bottom nav or the tablet drawer,
// and it used to get that wrong the moment someone turned their phone sideways.
//
// Runs on the Dart VM, so kIsWeb is false — i.e. these all exercise the NATIVE
// app paths. The web band is asserted only where it doesn't depend on kIsWeb.

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/widgets/Home/nav/nav_band.dart';

/// Logical sizes of real devices, portrait. Landscape is the same size flipped.
const _iphone14 = Size(390, 844);
const _pixel7 = Size(412, 915);
const _ipadMini = Size(744, 1133);
const _ipadPro = Size(1024, 1366);

Size _rotate(Size s) => Size(s.height, s.width);

void main() {
  group('phones stay on the bottom nav in both orientations', () {
    for (final (name, size) in [('iPhone 14', _iphone14), ('Pixel 7', _pixel7)]) {
      test('$name portrait', () {
        expect(resolveNavBand(size), NavBand.phone);
      });

      // The regression this rule exists for. A phone in landscape is ~844–915
      // wide, which sails past BOTH the 600 tablet line and the 900 top-nav
      // line. Deciding on width alone therefore handed a rotated phone the
      // desktop top nav in a ~390dp-tall viewport.
      test('$name landscape — still a phone, not a tablet or a desktop', () {
        expect(resolveNavBand(_rotate(size)), NavBand.phone);
      });
    }
  });

  group('tablets are not phones', () {
    test('iPad mini portrait → drawer', () {
      expect(resolveNavBand(_ipadMini), NavBand.drawer);
    });

    test('iPad mini landscape → top nav (1133 wide)', () {
      expect(resolveNavBand(_rotate(_ipadMini)), NavBand.topNav);
    });

    test('iPad Pro portrait → top nav (1024 wide)', () {
      expect(resolveNavBand(_ipadPro), NavBand.topNav);
    });
  });

  group('the shortest-side boundary', () {
    test('just under 600 is a phone', () {
      expect(resolveNavBand(const Size(599, 900)), NavBand.phone);
    });

    test('exactly 600 is not — the line is sw600dp, inclusive of tablets', () {
      expect(resolveNavBand(const Size(600, 900)), isNot(NavBand.phone));
    });
  });

  test('a phone is never given the top nav, however wide it gets', () {
    // Ordering guard: the phone check must short-circuit BEFORE the width-based
    // top-nav check, or a landscape phone matches both and the wider rule wins.
    for (final w in [900.0, 1000.0, 1400.0]) {
      expect(
        resolveNavBand(Size(w, 400)),
        NavBand.phone,
        reason: '${w}x400 has a 400dp shortest side — that is a handset',
      );
    }
  });
}
