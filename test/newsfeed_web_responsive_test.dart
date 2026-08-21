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
const double _oldColumnCap = 640;

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
      // The contract is "fits or is dropped", NOT "always shows the rail":
      // 900px leaves 852 of content and the pair needs 860, so the narrowest
      // few windows legitimately show the feed alone. What must hold at every
      // width is that nothing overflows and the rail is present exactly when
      // there is room for it.
      for (final viewport in <double>[900, 907, 908, 940, 1024, 1440, 1920]) {
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
    test('the column is a fixed multiple of the type base', () {
      // Not a pixel constant: the two move together, so retuning the base
      // cannot quietly lengthen or shorten the line. See kFeedMeasureRatio.
      expect(kFeedColumnMax, kFeedMetrics * kFeedMeasureRatio);
      expect(kFeedColumnMax, lessThan(_oldColumnCap));
      expect(
        kFeedMetrics,
        lessThan(kUiScaleMaxWidth),
        reason: 'the base must stay under the phone ceiling it replaced',
      );
    });

    test('full bleed and the measure are the same edge', () {
      // If these ever diverge, the band between them full-bleeds a slab wider
      // than the measure and the content SHRINKS as the window grows past it.
      expect(kPostCardFullBleedBelow, kFeedColumnMax);
    });

    test('body text stays in a readable measure at the phone type scale', () {
      // The point of the cap, in the unit that matters: characters per line.
      // ~30em is comfortable; the 640 column this replaced was ~45em.
      const bodySize = kFeedMetrics * 0.034;
      const gutter = kFeedMetrics * 0.035 * 2;
      final ems = (kFeedColumnMax - gutter) / bodySize;
      expect(ems, lessThan(36), reason: 'line runs long: ${ems.round()}em');

      final oldEms = (_oldColumnCap - gutter) / bodySize;
      expect(
        oldEms,
        greaterThan(ems),
        reason: 'sanity: the old column was the wider of the two',
      );
    });
  });
}
