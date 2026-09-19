// Does the STANDALONE (guest) web feed pick the right layout at every width?
//
// Three things are pinned here, and the first is the bug this file was written
// for.
//
//   1. The layout gate used to be `kIsWeb && rawWidth >= 900`, which left a
//      DEAD BAND from 481 to 899: a guest on a tablet, a split window or a
//      small laptop fell into the mobile arm, whose column is hard-capped at
//      480. The result was a phone-width strip marooned in grey with ~110px of
//      empty page either side at 700px, carrying the phone logo bar. A
//      signed-in citizen at that same width got the proper web body, because
//      the shell passes `embedded: true` and never consults the viewport — so
//      only the guest, who reaches this route standalone, ever saw it.
//
//      The gate now opens at 680, which reclaims 680..899. The rest of the old
//      band (481..679) deliberately STAYS on the mobile arm: its content box
//      cannot hold the measure either way, so the web body would draw the same
//      single column there. The fix targets the widths where a real second
//      column of page was going to waste, not every width that was ever below
//      the old threshold.
//
//   2. Widening the gate to 680 must not reintroduce the overflow that
//      [kFeedRailBelow] exists to prevent. The new band (680..1011) is below
//      the rail's threshold, so the rail must be ABSENT there rather than
//      crushed — the contract is "fits or is dropped".
//
//   3. The two thresholds must stay ordered. If the feed ever reached its web
//      body at a width narrower than a full-bleed post card wants, the arm
//      chosen and the card drawn inside it would disagree.
//
// Why these are value assertions rather than a pumped screen: the gate lives
// behind `kIsWeb`, a compile-time false under the VM, so no widget test can
// reach the real `build`. The arithmetic IS the bug, though — the old gate was
// wrong by a constant — so pinning the constants and the layout widget they
// feed catches a regression that a screenshot would only catch by luck. The
// rendered result was verified separately in a browser via
// tool/preview_guest_feed.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/widgets/Home/Newsfeed/feed_rail_layout.dart';
import 'package:govpulse/core/widgets/Home/Newsfeed/newsfeed_post_card.dart';

/// The page's own horizontal padding, from `_buildNewsFeedWebBody`.
const double _pagePadding = 24 * 2;

/// The mobile arm's hard cap, from the `ConstrainedBox` in the narrow branch of
/// `NewsFeedBody.build`. Not imported because it is an inline literal there;
/// restated so the dead band below is described in the numbers that caused it.
const double _mobileArmCap = 480;

const _feedKeyValue = Key('feed');
const _railKeyValue = Key('rail');

/// The content width a browser [viewport] wide leaves the layout.
double _contentFor(double viewport) =>
    (viewport < 1080 ? viewport : 1080) - _pagePadding;

/// Mirrors the wrapper `_buildNewsFeedWebBody` puts around [FeedRailLayout].
Future<void> _pumpWebBody(WidgetTester tester, double viewport) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = Size(viewport, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: const Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 56),
                child: FeedRailLayout(
                  feed: SizedBox(
                    key: _feedKeyValue,
                    height: 400,
                    width: double.infinity,
                  ),
                  rail: SizedBox(
                    key: _railKeyValue,
                    height: 200,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The gate as `NewsFeedBody.build` now computes it, with `kIsWeb` forced true
/// so the web arm is reachable from the VM.
bool _wideOnWeb(double rawWidth) => rawWidth >= kPostCardFullBleedBelow;

void main() {
  group('the guest feed reaches its web body on a tablet', () {
    test('the gate threshold is the measure, not 900', () {
      expect(
        kPostCardFullBleedBelow,
        680,
        reason: 'the gate is pinned to this; a change here moves the band',
      );
    });

    test('the recovered band now gets the web body', () {
      // The part of the old dead band the fix actually reclaims: 680..899.
      // These are the tablet / split-window / small-laptop widths that used to
      // draw a 480px phone column, and 700 is the width shot in the browser.
      for (final w in <double>[680, 700, 768, 820, 899]) {
        expect(
          _wideOnWeb(w),
          isTrue,
          reason: 'a ${w}px guest window still gets the phone column',
        );
      }
    });

    test('a phone browser keeps the mobile arm, and 481..679 stays with it', () {
      // Below the measure the mobile arm is genuinely right: its 480 cap and
      // full-bleed slabs are what a phone wants. This is the half of the gate
      // that must NOT change.
      //
      // 481..679 is deliberately still the mobile arm. It was part of the old
      // dead band, but the answer there is not "give it the web body" — a
      // 632px-or-narrower content box cannot hold the measure, so the web body
      // would draw the same single column with less of a gutter. What those
      // widths get instead is the mobile arm's own centred treatment, which is
      // what they already had. The fix targets the widths where a real second
      // column of page was going to waste.
      for (final w in <double>[320, 390, 414, 480, 481, 600, 679]) {
        expect(
          _wideOnWeb(w),
          isFalse,
          reason: 'a ${w}px phone browser lost its full-bleed arm',
        );
      }
    });

    test('the gate lands exactly on the measure', () {
      expect(_wideOnWeb(kPostCardFullBleedBelow - 1), isFalse);
      expect(_wideOnWeb(kPostCardFullBleedBelow), isTrue);
    });

    test('the mobile cap was the thing stranding the old band', () {
      // Documents the defect's shape: at 700px the old arm drew 480 and left
      // 220 of empty page. If either constant moves, this stops describing it.
      expect(_mobileArmCap, lessThan(kPostCardFullBleedBelow));
      expect(700 - _mobileArmCap, 220);
    });
  });

  group('the widened band does not overflow', () {
    testWidgets('no rail, and no exception, across the whole new band', (
      tester,
    ) async {
      // The band the gate just opened up. The rail needs 1012 of content, so
      // every one of these legitimately shows the feed alone — what must hold
      // is that nothing overflows on the way.
      for (final viewport in <double>[680, 700, 768, 820, 899, 1000]) {
        await _pumpWebBody(tester, viewport);
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflowed at a ${viewport}px guest window',
        );
        expect(
          find.byKey(_railKeyValue),
          findsNothing,
          reason: 'the rail cannot fit at ${viewport}px and must be dropped',
        );
        expect(find.byKey(_feedKeyValue), findsOneWidget);
      }
    });

    testWidgets('the feed never exceeds the measure in the new band', (
      tester,
    ) async {
      // At 680 the content box is 632, so the column takes what it is given;
      // past that it is capped. Either way it must never exceed the measure.
      for (final viewport in <double>[680, 820, 1000]) {
        await _pumpWebBody(tester, viewport);
        final width = tester.getSize(find.byKey(_feedKeyValue)).width;
        expect(
          width,
          lessThanOrEqualTo(kFeedColumnMax),
          reason: 'the column ran past the measure at ${viewport}px',
        );
        expect(
          width,
          _contentFor(viewport) >= kFeedColumnMax
              ? kFeedColumnMax
              : _contentFor(viewport),
          reason: 'the column is not filling its box at ${viewport}px',
        );
      }
    });

    testWidgets('the rail returns once there is room for it', (tester) async {
      // The other side of the contract: widening the gate must not have cost
      // the rail at the widths that can hold it.
      for (final viewport in <double>[1060, 1280, 1920]) {
        await _pumpWebBody(tester, viewport);
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(_railKeyValue),
          findsOneWidget,
          reason: 'the rail went missing at a ${viewport}px window',
        );
      }
    });
  });

  group('the thresholds stay ordered', () {
    test('the web body is only entered at or above the full-bleed width', () {
      // The arm chosen and the card drawn inside it must agree: the web body
      // must never be entered at a width narrower than a full-bleed card wants.
      expect(kPostCardFullBleedBelow, kFeedColumnMax);
      expect(kFeedRailBelow, greaterThan(kPostCardFullBleedBelow));
    });
  });
}
