import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:govpulse/features/landing/sections/landing_features.dart';

// ════════════════════════════════════════════════════════════════════════════
//  The Features ring's seven labels do not sit on top of each other.
//
//  ── The bug this exists for ────────────────────────────────────────────────
//  The ring is a Stack of absolutely-positioned labels around two overlapping
//  device shots. A Stack NEVER reports a collision: two children given the same
//  region simply paint over one another, so "Get instant assistance and answers
//  from authorized LGU staff." rendered underneath the LGU Updates megaphone and
//  "Quick access to hotlines and emergency services when you need them." ran
//  under the Suggestion disc — with `flutter analyze` clean, the whole landing
//  suite green, and no overflow stripe anywhere.
//
//  Nothing in the existing tests could have caught it. landing_responsive_test
//  sweeps thirteen widths looking for OVERFLOW, which is a different failure:
//  an overlapping Stack child is perfectly laid out, just illegible. It took a
//  screenshot to see, and a screenshot is not something CI can diff.
//
//  So this asserts the property directly — every pair of label boxes is
//  disjoint — which is what "the ring is readable" actually means in pixels.
//
//  ── Why a tolerance, and why it is small ───────────────────────────────────
//  Each item's box is the Column around its icon, title and body. The bodies
//  are centred within their measure, so two boxes can touch at the corners
//  while the INK inside them stays well clear. A few pixels of box overlap is
//  therefore not a defect. Anything more is: the text in these labels runs the
//  full width of its box, so a real overlap is ink on ink.
// ════════════════════════════════════════════════════════════════════════════

/// Widths at which the ring layout is used. Below [LandingUi.ringBreak] the
/// section switches to a grid, which cannot collide by construction.
///
/// ── 1180 and 1181 are both here on purpose ─────────────────────────────────
/// 1180 is the tightest possible ring, and it is the ONLY width that caught a
/// real collision when the slot table had been solved against the wrong band.
/// [LandingBand] applies its gutter before the maxWidth clamp, so at a 1180
/// viewport the ring gets 1180 - 2*24 = 1132, while at every wider viewport the
/// clamp wins and it gets the full 1180. A table solved for 1180 therefore
/// passed everywhere except at exactly the breakpoint.
///
/// ── The sub-1180 widths are the NEW ring range ─────────────────────────────
/// The ring used to fold at 1180. It now runs to [LandingUi.ringBreak] (940),
/// with the phone shrinking to make room rather than the labels — so 940..1179
/// is a range that was never a ring before and is where a regression would land
/// first. 940 and 941 bracket the breakpoint itself for the same reason 1180
/// and 1181 do.
///
/// 2560 covers a large desktop, where the scale factor in _FeatureRing is
/// clamped and the composition stops growing.
const List<double> _ringWidths = <double>[
  940,
  941,
  1000,
  1069,
  1100,
  1179,
  1180,
  1181,
  1280,
  1440,
  1600,
  1920,
  2560,
];

/// How much two label boxes may overlap before it counts as a collision.
const double _tolerance = 6.0;

Widget _host(Size size) => MediaQuery(
  data: MediaQueryData(size: size),
  child: const MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: LandingFeatures()),
    ),
  ),
);

/// The on-screen box of each of the seven feature labels, found by locating the
/// title Text of each and walking up to the enclosing item Column.
List<({String title, Rect rect})> _labelBoxes(WidgetTester tester) {
  final out = <({String title, Rect rect})>[];
  for (final feature in LandingFeatures.features) {
    final title = find.text(feature.title);
    expect(
      title,
      findsOneWidget,
      reason: 'the ring should render "${feature.title}" exactly once',
    );
    // The item's own Column is the nearest ancestor Column of its title.
    final column = find.ancestor(of: title, matching: find.byType(Column));
    final box = tester.renderObject<RenderBox>(column.first);
    final topLeft = box.localToGlobal(Offset.zero);
    out.add((title: feature.title, rect: topLeft & box.size));
  }
  return out;
}

void main() {
  for (final width in _ringWidths) {
    testWidgets('ring labels do not overlap at $width', (tester) async {
      // Tall enough that the whole ring is laid out in one frame — this is a
      // geometry test, not a scrolling one.
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(Size(width, 2400)));
      await tester.pumpAndSettle();

      final boxes = _labelBoxes(tester);
      expect(boxes.length, LandingFeatures.features.length);

      for (var i = 0; i < boxes.length; i++) {
        for (var j = i + 1; j < boxes.length; j++) {
          final a = boxes[i];
          final b = boxes[j];
          final overlap = a.rect.intersect(b.rect);
          // A negative width or height means the rects are disjoint on that
          // axis, which is the passing case.
          final collides =
              overlap.width > _tolerance && overlap.height > _tolerance;
          expect(
            collides,
            isFalse,
            reason:
                'at ${width.toInt()}px "${a.title}" ${a.rect} overlaps '
                '"${b.title}" ${b.rect} by '
                '${overlap.width.toStringAsFixed(1)}x'
                '${overlap.height.toStringAsFixed(1)}px — one label is '
                'painting over the other in the ring Stack',
          );
        }
      }
    });
  }

  // ── Labels must also clear the DEVICE ARTWORK ────────────────────────────
  // Label-vs-label is only half the ring's geometry. The phones sit in the same
  // Stack, and a label that lands on them is just as unreadable — worse, in
  // fact, because the artwork is dark and busy where a neighbouring label is at
  // least white space.
  //
  // This gap was real, not hypothetical: enlarging the labels and the phone
  // together pushed "Quick access to hotlines and emergency services when you
  // need them." onto the splash screen, and every label-vs-label assertion
  // above still passed.
  //
  // The phone's BOX is larger than the devices drawn inside it — the artwork
  // has its own transparent margin and the two devices only span part of the
  // frame — so a small intrusion into the box is not necessarily ink on ink.
  // The tolerance is generous for that reason; what it catches is a label
  // sitting squarely on the artwork.
  for (final width in _ringWidths) {
    testWidgets('ring labels clear the device art at $width', (tester) async {
      tester.view.physicalSize = Size(width, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(Size(width, 2600)));
      await tester.pumpAndSettle();

      // The device pair is the AspectRatio inside the ring — but its BOX is
      // bigger than the devices drawn in it. The two phones are placed at
      // widthFactor 0.46 either side of centre, so measured against the box the
      // artwork actually occupies x 0.09..0.89 and y 0.12..0.87; the rest is the
      // glow and transparent margin, which a label may sit over harmlessly.
      //
      // Testing the whole box instead would fail layouts that look perfectly
      // clean, and — worse — would push the ring taller to satisfy a constraint
      // that is not real.
      final art = tester.renderObject<RenderBox>(find.byType(AspectRatio).first);
      final box = art.localToGlobal(Offset.zero) & art.size;
      final artRect = Rect.fromLTRB(
        box.left + box.width * 0.09,
        box.top + box.height * 0.12,
        box.left + box.width * 0.89,
        box.top + box.height * 0.87,
      );

      for (final label in _labelBoxes(tester)) {
        final overlap = label.rect.intersect(artRect);
        final collides = overlap.width > 16 && overlap.height > 16;
        expect(
          collides,
          isFalse,
          reason:
              'at ${width.toInt()}px "${label.title}" ${label.rect} sits on '
              'the device artwork $artRect, overlapping by '
              '${overlap.width.toStringAsFixed(0)}x'
              '${overlap.height.toStringAsFixed(0)}px',
        );
      }
    });
  }

  // ── The ring reserves no more height than it PAINTS ──────────────────────
  // The ring's height is a solve constant: the canvas its slot fractions are
  // measured against. But the outermost slots are -0.83 and +0.70, and Align
  // centres a child at its fraction of the FREE space, so the labels stop well
  // short of the container's edges. Reserving the full solve height therefore
  // left ~200px of unpainted white inside the section — a band above and below
  // the composition that read as a broken gap before the next section.
  //
  // Nothing caught that either: the layout is valid, no label overlaps, no
  // overflow. It is only visible against the sections around it.
  //
  // _FeatureRing now paints into a box trimmed by two hand-derived fractions.
  // This asserts those fractions still match the content, so that if a slot or
  // the item measure ever moves, the trim is stale and this fails rather than
  // the gap quietly reopening.
  for (final width in _ringWidths) {
    testWidgets('ring reserves no dead space at $width', (tester) async {
      tester.view.physicalSize = Size(width, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(Size(width, 2600)));
      await tester.pumpAndSettle();

      // The union of everything actually drawn: the seven labels and the art.
      Rect? content;
      for (final label in _labelBoxes(tester)) {
        content = content == null
            ? label.rect
            : content.expandToInclude(label.rect);
      }
      final art = tester.renderObject<RenderBox>(find.byType(AspectRatio).first);
      content = content!.expandToInclude(
        art.localToGlobal(Offset.zero) & art.size,
      );

      // The box the section actually reserves in the page.
      final reserved = tester.renderObject<RenderBox>(
        find.byType(OverflowBox).first,
      );
      final reservedRect =
          reserved.localToGlobal(Offset.zero) & reserved.size;

      final above = content.top - reservedRect.top;
      final below = reservedRect.bottom - content.bottom;

      // A ring is a composition, not a tight crop — a little breathing room
      // above and below is correct. What is not correct is the ~130px band the
      // untrimmed solve height left. 48 is comfortably more than the intended
      // margin and far less than the defect.
      expect(
        below,
        lessThan(48),
        reason:
            'at ${width.toInt()}px the ring reserves ${below.toStringAsFixed(0)}px '
            'of unpainted space BELOW its content — the trim fractions no longer '
            'match the slot table',
      );
      expect(
        above,
        lessThan(48),
        reason:
            'at ${width.toInt()}px the ring reserves ${above.toStringAsFixed(0)}px '
            'of unpainted space ABOVE its content — the trim fractions no longer '
            'match the slot table',
      );
      // And the content must not be CLIPPED by an over-aggressive trim.
      expect(
        above,
        greaterThan(-1),
        reason: 'at ${width.toInt()}px the ring trims into its own content',
      );
      expect(
        below,
        greaterThan(-1),
        reason: 'at ${width.toInt()}px the ring trims into its own content',
      );
    });
  }

  // ── The narrow grid, across the whole range below the ring ───────────────
  // The ring gets all the geometry attention because it is the hard layout, but
  // every width below LandingUi.ringBreak uses the grid, and that is most
  // phones and every tablet. These assert what actually breaks there: content
  // that does not fit the width it was given, a device image that has collapsed
  // or run away with the page, and cards in a row that do not share a height.
  //
  // Every width here must be BELOW LandingUi.ringBreak. 1024 and 1179 were in
  // this list while the ring folded at 1180; they are rings now, and left here
  // they would assert grid geometry against a ring — passing or failing for
  // reasons that have nothing to do with the grid.
  //
  // Widths chosen to cross every grid boundary: 1 column below 460, 2 up to
  // 820, 3 up to the ring break. 459/460 and 819/820 bracket the two column
  // changes, because an off-by-one there is invisible on any other width.
  for (final width in <double>[
    320,
    360,
    390,
    430,
    459,
    460,
    535,
    560,
    768,
    801,
    819,
    820,
    900,
    913,
    939,
  ]) {
    testWidgets('grid lays out cleanly at $width', (tester) async {
      tester.view.physicalSize = Size(width, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(Size(width, 2600)));
      await tester.pumpAndSettle();

      // No overflow stripe anywhere in the section.
      expect(tester.takeException(), isNull);

      // Every feature is present and readable at every size — the grid must
      // never drop one to make room.
      for (final feature in LandingFeatures.features) {
        expect(
          find.text(feature.title),
          findsOneWidget,
          reason: '"${feature.title}" is missing at ${width.toInt()}px',
        );
      }

      // The device pair scales with the page rather than stepping. Its box is
      // a fraction of the available width, clamped — so it must always be a
      // sane size, never zero (a collapsed AspectRatio) and never wider than
      // the screen.
      final phone = find.byType(AspectRatio);
      expect(phone, findsWidgets);
      final box = tester.renderObject<RenderBox>(phone.first);
      expect(
        box.size.width,
        greaterThanOrEqualTo(200),
        reason: 'device art collapsed at ${width.toInt()}px',
      );
      expect(
        box.size.width,
        lessThanOrEqualTo(width),
        reason: 'device art is wider than the screen at ${width.toInt()}px',
      );

      // ── Cards sharing a row share a height ─────────────────────────────
      // The grid was a Wrap, which gives every child its natural height, so
      // two cards side by side ended at different depths whenever their bodies
      // wrapped to a different number of lines — a ragged bottom edge on every
      // row. Nothing caught it: the layout is valid, there is no overflow, and
      // every title is present. It took a screenshot to see.
      //
      // Cards are grouped into rows by their TOP edge rather than by index,
      // because the test should not have to know the column count — that is
      // the thing most likely to change.
      final cardTops = <double, List<double>>{};
      for (final feature in LandingFeatures.features) {
        final card = find
            .ancestor(
              of: find.text(feature.title),
              matching: find.byType(Container),
            )
            .first;
        final r = tester.renderObject<RenderBox>(card);
        final top = r.localToGlobal(Offset.zero).dy;
        // Round, so sub-pixel differences do not split one row into two.
        final key = (top / 4).roundToDouble();
        (cardTops[key] ??= <double>[]).add(r.size.height);
      }
      for (final entry in cardTops.entries) {
        final heights = entry.value;
        if (heights.length < 2) continue;
        final min = heights.reduce((a, b) => a < b ? a : b);
        final max = heights.reduce((a, b) => a > b ? a : b);
        expect(
          max - min,
          lessThanOrEqualTo(1.0),
          reason:
              'at ${width.toInt()}px cards in one row have different heights '
              '($heights) — the row has a ragged bottom edge',
        );
      }
    });
  }

  testWidgets('every feature appears exactly once in the ring', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const Size(1440, 2400)));
    await tester.pumpAndSettle();

    // Seven, not six: Feedback is a real quick action and the design carries it
    // at the bottom of the ring. It was dropped once, which both diverged from
    // the mockup and left a visible hole on the right.
    expect(LandingFeatures.features.length, 7);
    for (final feature in LandingFeatures.features) {
      expect(find.text(feature.title), findsOneWidget);
      expect(find.text(feature.body), findsOneWidget);
    }
  });
}
