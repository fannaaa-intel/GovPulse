// Does the WEB feed lay out correctly on a medium and a large screen?
//
// Two defects are pinned here, and the first is a live overflow.
//
//   1. The standalone (guest) web feed switches to its two-column layout at a
//      900px viewport and then laid out FIXED boxes with nothing checking they
//      fit: 600 + 32 + 300 = 932, inside a box only `viewport - 48` wide. Every
//      window from 900 to 979 overflowed its Row. It survived because the
//      layout sits behind a `kIsWeb && rawWidth >= 900` gate and `kIsWeb` is a
//      compile-time false under the VM, so no widget test could reach it —
//      which is why it is a widget now ([FeedRailLayout]) rather than an inline
//      branch, and why these cases pump it at explicit widths.
//
//   2. Nothing capped the feed column to a readable MEASURE. That was survivable
//      while the type was sized off a 480 base; once kFeedMetrics brought the
//      type down to a phone scale, a 640px column ran body text to ~100
//      characters a line. Nothing overflows — it is simply wrong on a large
//      screen, which is exactly the kind of thing a "does it fit?" test misses
//      and an explicit measure assertion does not.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:govpulse/core/theme/mobile_metrics.dart';
import 'package:govpulse/core/widgets/Home/Newsfeed/feed_rail_layout.dart';
import 'package:govpulse/core/widgets/Home/Newsfeed/newsfeed_post_card.dart';

/// The page's own horizontal padding, from `_buildNewsFeedWebBody`.
const double _pagePadding = 24 * 2;

/// The fixed widths the layout used before, kept as the regression's shape.
const double _oldFeedWidth = 600;

/// Facebook's feed geometry, measured off a screenshot at a 1919px window: the
/// post card runs 613..1291, its body text is 15px, its card padding 12px.
/// This feed is matched to it, so these are the reference the tests check.
const double _facebookColumn = 678;
const double _facebookBodySize = 15;
const double _facebookGutter = 12;

const _feedKeyValue = Key('feed');
const _railKeyValue = Key('rail');

/// Pumps [FeedRailLayout] inside the page wrapper `_buildNewsFeedWebBody`
/// gives it, at a browser [viewport] wide.
///
/// The view size is set rather than a SizedBox wrapped around the subject: the
/// test surface defaults to 800x600, so any box asked for more than 800 is
/// quietly clamped to it — which silently turns "a 1440px desktop" into "800px"
/// and every wide case into the same narrow one.
Future<void> _pumpLayout(WidgetTester tester, double viewport) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = Size(viewport, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            // The page's own wrapper, mirrored: a 1080 cap and 24px of side
            // padding. The children see `min(viewport, 1080) - 48`.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 56),
                child: FeedRailLayout(
                  // `double.infinity` so the stubs take whatever width they are
                  // offered, exactly as the real feed and rail do. A bare
                  // SizedBox with only a height measures 0 wide and would make
                  // every width assertion below trivially pass at nothing.
                  feed: const SizedBox(
                    key: _feedKeyValue,
                    height: 400,
                    width: double.infinity,
                  ),
                  rail: const SizedBox(
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

/// The content width a browser [viewport] wide leaves the layout.
double _contentFor(double viewport) =>
    (viewport < 1080 ? viewport : 1080) - _pagePadding;

void main() {
  group('the rail fits or goes', () {
    testWidgets('a 900px window no longer overflows', (tester) async {
      // The exact width the two-column layout first switches on — and the
      // width the old fixed Row overflowed by 80px.
      await _pumpLayout(tester, 900);

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(_feedKeyValue)).width,
        kFeedColumnMax,
        reason: 'the feed column is the measure, not the leftover room',
      );
    });

    testWidgets('every window from 900 up is clean, with or without the rail', (
      tester,
    ) async {
      // The contract is "fits or is dropped", NOT "always shows the rail".
      // Now that the column is Facebook's 680, the pair needs 1012 of content,
      // so everything up to a 1059px window legitimately shows the feed alone —
      // including a 1024 laptop. What must hold at every width is that nothing
      // overflows and the rail is present exactly when there is room for it.
      // 1059/1060 straddle that edge on purpose.
      for (final viewport in <double>[900, 1024, 1059, 1060, 1280, 1920]) {
        await _pumpLayout(tester, viewport);
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflowed at a ${viewport}px window',
        );
        expect(
          find.byKey(_railKeyValue),
          _contentFor(viewport) >= kFeedRailBelow
              ? findsOneWidget
              : findsNothing,
          reason: 'rail presence is wrong at a ${viewport}px window',
        );
      }
    });

    testWidgets('the rail is dropped rather than crushed when it cannot fit', (
      tester,
    ) async {
      // One pixel under the pair's own width: the feed keeps the full measure
      // and the rail is gone, instead of both being squeezed into an overflow.
      await _pumpLayout(tester, kFeedRailBelow - 1 + _pagePadding);

      expect(tester.takeException(), isNull);
      expect(find.byKey(_railKeyValue), findsNothing);
      expect(find.byKey(_feedKeyValue), findsOneWidget);
      expect(tester.getSize(find.byKey(_feedKeyValue)).width, kFeedColumnMax);
    });

    testWidgets(
      'a narrow box still never stretches the feed past the measure',
      (tester) async {
        await _pumpLayout(tester, 700 + _pagePadding);
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(_feedKeyValue)).width,
          kFeedColumnMax,
          reason: '700px of room is not a reason for a 700px line of text',
        );
      },
    );

    test('the guard is the pair own width, with no fudge in it', () {
      // The threshold must BE what the children need. The old layout's bug was
      // exactly this number going unstated: 600 + 32 + 300 laid out in a box
      // that could not hold it.
      expect(kFeedRailBelow, kFeedColumnMax + kFeedRailGap + kFeedRailWidth);
      expect(
        _oldFeedWidth + kFeedRailGap + kFeedRailWidth,
        greaterThan(_contentFor(900)),
        reason: 'the old widths should still demonstrate the overflow',
      );
    });
  });

  group('the measure', () {
    test('the column is the Facebook feed column', () {
      // Measured off Facebook at a 1919px window: its post card runs 613..1291.
      // closeTo, not equality: 678 is what a screenshot measures, 680 is the
      // value the design is built on. A few pixels of ruler error is not a
      // reason to encode 678 into the app.
      expect(kFeedColumnMax, closeTo(_facebookColumn, 4));
      expect(
        kFeedMetrics,
        lessThan(kUiScaleMaxWidth),
        reason: 'the base must stay under the phone ceiling it replaced',
      );
    });

    test('a 600px-class window gets the phone treatment', () {
      // 600, and the ~606 a half-screen browser actually reports, are small
      // screens: the post runs edge to edge there rather than sitting as a card
      // that cannot reach its own measure anyway.
      for (final column in <double>[411, 500, 600, 606, 668]) {
        expect(
          column < kPostCardFullBleedBelow,
          isTrue,
          reason: 'a $column column should be full bleed',
        );
      }
      // ...and the widths that CAN hold the full column still get the card.
      for (final column in <double>[720, 900, 1004, 1220]) {
        expect(
          column < kPostCardFullBleedBelow,
          isFalse,
          reason: 'a $column column should be a centred card',
        );
      }
    });

    test('content only ever grows with the window', () {
      // The invariant, and the reason these two are not free to move apart:
      // while full bleed ends at or before the column cap, the content widens
      // monotonically — slab to 480, then a card out to 680. If the threshold
      // were the LARGER, the band between them would full-bleed something
      // wider than the column and content would SHRINK as the window grew.
      expect(kPostCardFullBleedBelow, lessThanOrEqualTo(kFeedColumnMax));
    });

    test('body text lands on the Facebook size and measure', () {
      const bodySize = kFeedMetrics * 0.034;
      const gutter = kFeedMetrics * 0.035 * 2;

      // The one number that matters most, and it is a match, not an
      // approximation: Facebook sets post body text at 15px.
      expect(bodySize, closeTo(_facebookBodySize, 0.1));

      // The resulting line length is WIDE — ~43em — and that is intentional,
      // because it is Facebook's. Asserted as a band around Facebook's own
      // measure rather than against a typographic ideal, so that nobody later
      // "fixes" the column back down and quietly un-matches the reference.
      final ems = (kFeedColumnMax - gutter) / bodySize;
      final fbEms = (_facebookColumn - _facebookGutter * 2) / _facebookBodySize;
      expect(
        ems,
        closeTo(fbEms, 3),
        reason:
            'measure drifted from Facebook: ${ems.round()}em '
            'vs ${fbEms.round()}em',
      );
    });
  });
}
