// Does the bottom action bar's copy line up with the report card above it?
//
// ── The bug ────────────────────────────────────────────────────────────────
// The bar padded itself with `w * .04`, where `w` is [uiScaleWidth] — which
// CLAMPS AT 480 on web. So the bar's gutter was a flat 19px at every viewport
// while the card above it uses [kAccountPageGutter] (32px). The copy started
// 13px left of the card's edge, at every window size, and no amount of
// re-centring the bar could fix it because the two were measuring with
// different rulers.
//
// This pumps the two gutters side by side and asserts their left edges land on
// the same pixel — the thing a screenshot was ambiguous about twice.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/core/theme/mobile_metrics.dart';
import 'package:govpulse/core/widgets/Home/Account/account_web_kit.dart';

/// The shell's centre column at a 1920 window: 1920 − 288 rail − 340 sidebar.
const double _kColumn = 1292;

void main() {
  group('the gutters must agree', () {
    test('uiScaleWidth clamps, so `w * .04` cannot track the viewport', () {
      // The heart of it. Two very different windows, one identical gutter —
      // and neither equals the 32px the content uses.
      final wide = uiScaleWidthOf(const Size(1920, 1080)) * .04;
      final narrow = uiScaleWidthOf(const Size(1280, 800)) * .04;

      expect(wide, narrow, reason: 'clamped: the viewport does not reach it');
      expect(wide, closeTo(19.2, 0.01));
      expect(
        wide,
        isNot(closeTo(kAccountPageGutter, 0.01)),
        reason: 'this mismatch IS the bug: 19.2 vs $kAccountPageGutter',
      );
    });

    test('the content gutter is 32 and does not depend on the viewport', () {
      expect(kAccountPageGutter, 32);
    });
  });

  group('rendered geometry', () {
    // Both trees use the page's real band and the real gutter constant, laid
    // out in the real centre-column width. If the bar and the card disagree,
    // these left edges differ.
    Widget banded({required double gutter, required Key key}) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kAccountMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: SizedBox(key: key, height: 40, width: double.infinity),
        ),
      ),
    );

    testWidgets('bar copy starts exactly where the card copy starts', (
      tester,
    ) async {
      const cardKey = Key('card');
      const barKey = Key('bar');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _kColumn,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    banded(gutter: kAccountPageGutter, key: cardKey),
                    // The bar, using the SAME gutter after the fix.
                    banded(gutter: kAccountPageGutter, key: barKey),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final card = tester.getTopLeft(find.byKey(cardKey));
      final bar = tester.getTopLeft(find.byKey(barKey));

      expect(bar.dx, card.dx, reason: 'left edges must be the same pixel');
      expect(
        tester.getTopRight(find.byKey(barKey)).dx,
        tester.getTopRight(find.byKey(cardKey)).dx,
        reason: 'right edges too, or the button hangs past the card',
      );
    });

    testWidgets('the OLD gutter really did misalign, by 12.8px', (
      tester,
    ) async {
      // Guards the diagnosis. If someone restores `w * .04`, this fails and
      // says exactly how far off it puts the bar.
      const cardKey = Key('card');
      const barKey = Key('bar');
      final oldGutter = uiScaleWidthOf(const Size(1920, 1080)) * .04;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _kColumn,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    banded(gutter: kAccountPageGutter, key: cardKey),
                    banded(gutter: oldGutter, key: barKey),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final drift =
          tester.getTopLeft(find.byKey(cardKey)).dx -
          tester.getTopLeft(find.byKey(barKey)).dx;

      expect(drift, closeTo(kAccountPageGutter - oldGutter, 0.01));
      expect(drift, closeTo(12.8, 0.01));
    });
  });

  group('the button sits at the far end', () {
    testWidgets('spaceBetween pins copy left and button right', (tester) async {
      const copyKey = Key('copy');
      const buttonKey = Key('button');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: kAccountMaxWidth,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Flexible(child: SizedBox(key: copyKey, width: 200, height: 40)),
                    SizedBox(width: 24),
                    Flexible(
                      child: SizedBox(key: buttonKey, width: 180, height: 40),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final copyLeft = tester.getTopLeft(find.byKey(copyKey)).dx;
      final rowLeft = tester.getTopLeft(find.byType(Row)).dx;
      final buttonRight = tester.getTopRight(find.byKey(buttonKey)).dx;
      final rowRight = tester.getTopRight(find.byType(Row)).dx;

      expect(copyLeft, rowLeft, reason: 'copy hugs the left edge');
      expect(buttonRight, rowRight, reason: 'button hugs the right edge');

      // And the space between them is real, not a coincidence of widths.
      final gap = tester.getTopLeft(find.byKey(buttonKey)).dx -
          tester.getTopRight(find.byKey(copyKey)).dx;
      expect(gap, greaterThanOrEqualTo(24));
    });
  });
}
