import 'package:flutter/material.dart';

import '../landing_page.dart'
    show LandingBand, LandingEyebrow, LandingHeading, LandingSubhead;
import '../landing_theme.dart';
import '../widgets/reveal_on_scroll.dart';

/// The six capabilities.
///
/// ── The ring, and why it collapses ─────────────────────────────────────────
/// The design arranges six labelled icons in a ring around a floating phone —
/// three down each side on a wide screen. That composition is the whole visual
/// idea of the section, so it is preserved down to [LandingUi.ringBreak].
///
/// ── The ring reaches further down than it used to ──────────────────────────
/// It once folded at [LandingUi.tabletBreak], and the note here claimed a
/// narrower ring "either overlaps the phone or shrinks the labels past reading
/// size". Half of that was right. Forcing the ring below its breakpoint and
/// measuring showed label pairs stay disjoint all the way to 900 — the slot
/// table is in fractions, so it contracts on its own — while what actually
/// breaks is labels landing on the DEVICE ART, because the phone was the one
/// element sized in pixels rather than fractions.
///
/// So the phone yields instead (see `_kPhoneFloor`), and the ring now serves
/// every medium screen down to 940 rather than handing a 1000px laptop the
/// phone-shaped card grid.
///
/// Below [LandingUi.ringBreak] it still becomes a GRID, not a squeezed ring:
/// past that point the labels genuinely do start colliding with each other. The
/// grid keeps every item at full size and simply reflows — two columns on a
/// tablet, one on a phone.
class LandingFeatures extends StatelessWidget {
  const LandingFeatures({super.key});

  /// The six, in the design's reading order: left column top-to-bottom, then
  /// right column. Order is load-bearing for the ring layout below.
  static const List<LandingFeature> features = <LandingFeature>[
    LandingFeature(
      asset: 'assets/images/landing/icon_report.webp',
      tint: Color(0xFFE8F1FE),
      title: 'Report Issue',
      body: 'Easily report problems in your area and track their status.',
    ),
    LandingFeature(
      asset: 'assets/images/landing/icon_chat.webp',
      tint: Color(0xFFE9EDFD),
      title: 'Chat with Agent',
      body: 'Get instant assistance and answers from authorized LGU staff.',
    ),
    LandingFeature(
      asset: 'assets/images/landing/icon_updates.webp',
      tint: Color(0xFFE7F8EE),
      title: 'LGU Updates',
      body: 'Stay informed with the latest announcements and advisories.',
    ),
    LandingFeature(
      asset: 'assets/images/landing/icon_emergency.webp',
      tint: Color(0xFFFDECEC),
      title: 'Emergency',
      body:
          'Quick access to hotlines and emergency services when you need them.',
    ),
    LandingFeature(
      asset: 'assets/images/landing/icon_suggestion.webp',
      tint: Color(0xFFEAF3FB),
      title: 'Suggestion',
      body: 'Share your ideas and help improve community services.',
    ),
    LandingFeature(
      asset: 'assets/images/landing/icon_events.webp',
      tint: Color(0xFFFFF6E6),
      title: 'Events and Activities',
      body: 'Discover upcoming events and activities in your community.',
    ),
    // SEVEN, not six. The design's ring carries Feedback at the bottom centre,
    // and it is a real quick action in the app (features/home/Quick-action/
    // Feedback) — dropping it both diverged from the mockup and left a visible
    // hole on the right of the ring.
    LandingFeature(
      asset: 'assets/images/landing/icon_feedback.webp',
      tint: Color(0xFFE8F1FE),
      title: 'Feedback',
      body: 'Share your feedback and help improve LGU services.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= LandingUi.ringBreak;
    final narrow = width < LandingUi.mobileBreak;

    return LandingBand(
      background: LandingUi.surface,
      padding: EdgeInsets.symmetric(
        vertical: narrow ? 64 : 88,
        horizontal: LandingUi.gutter,
      ),
      child: Column(
        children: [
          const RevealOnScroll(child: LandingEyebrow('Features')),
          const SizedBox(height: 18),
          const RevealOnScroll(
            delay: Duration(milliseconds: 60),
            child: LandingHeading(
              lead: 'Designed for Citizens, ',
              highlight: 'Built for Communities',
            ),
          ),
          const SizedBox(height: 16),
          const RevealOnScroll(
            delay: Duration(milliseconds: 110),
            child: LandingSubhead(
              'Powerful tools that help people stay informed, connected, '
              'and involved.',
            ),
          ),
          SizedBox(height: narrow ? 40 : 56),
          if (wide) const _FeatureRing() else _FeatureGrid(narrow: narrow),
        ],
      ),
    );
  }
}

/// The wide composition: six labelled features arranged AROUND the devices.
///
/// ── A real ring, not two columns ───────────────────────────────────────────
/// The design places its six items on a circle: Report Issue sits at the top
/// centre, Events and Activities at the bottom centre, and the remaining four
/// fall away down the two sides. The first build approximated that with two
/// straight columns and a small horizontal nudge, which read as three rows of
/// two — recognisably not the mockup.
///
/// This positions each item by ANGLE instead. [_kSlots] is the design's own
/// arrangement measured off the artboard, as (x, y) in [Alignment] space where
/// -1 is the left/top edge and +1 the right/bottom. Reading them in order walks
/// clockwise from the top:
///
///     Report Issue      top, just left of centre
///     Emergency         upper right
///     Suggestion        lower right
///     Events            bottom, just right of centre
///     LGU Updates       lower left
///     Chat with Agent   upper left
///
/// A [Stack] rather than Rows and Columns, because that is what "position by
/// angle" means — there is no row or column here to belong to, and forcing one
/// is exactly what produced the grid look.
class _FeatureRing extends StatelessWidget {
  const _FeatureRing();

  /// Where each feature sits, in [Alignment] space, and how its text is
  /// justified. Index matches [LandingFeatures.features].
  ///
  /// `align` is the edge the label hugs so that every item leans AWAY from the
  /// devices in the centre: items on the left are right-aligned, items on the
  /// right are left-aligned, and the two nearest the vertical axis are centred.
  ///
  /// ── The vertical gaps are a COLLISION constraint, not a taste one ───────
  /// A [Stack] never reports a collision: two children given overlapping
  /// regions simply paint over each other. So the arithmetic has to be done
  /// here, and it is unforgiving.
  ///
  /// An item is an icon (58) plus a title and its body. [Align] spreads -1..1
  /// across the FREE space, `H - h`, so a child at slot `a` has its centre at
  /// `h/2 + (0.5 + a/2) * (H - h)`. Two items on the same side are disjoint
  /// only if their centres are at least `h` apart.
  ///
  /// The consequence is a hard floor: N items stacked down one side need a ring
  /// of at least `N * h`.
  ///
  /// `h` IS NOT A CONSTANT — it is set by [_FeatureItem]'s measure, because the
  /// measure decides how many lines each body wraps to, and the seven bodies
  /// are different lengths. Predicting it from font metrics failed repeatedly
  /// here; the only reliable value is the one a test prints. At the current
  /// measure the tallest items render 239px.
  ///
  /// The table is the mockup's own fractions (below) run through a search for
  /// stretch factors that leave all 21 pairs disjoint: x1.20 on x, x1.20 on y,
  /// at [_kRingHeight]. Nudging one slot by hand tends to fix one collision and
  /// open another — an early fix cleared Chat/LGU Updates and immediately broke
  /// LGU Updates/Events.
  ///
  /// ── DO NOT RE-SOLVE THIS TO ABSORB A SIZE CHANGE ────────────────────────
  /// Type was once raised from 15.5/13.5 to 17/15, and the whole table was
  /// re-solved to fit: the measure went to 264, the ring to 1210. Every test
  /// passed and the composition was RUINED — the labels spread into three loose
  /// rows with a small phone parked in the middle, nothing like the design's
  /// tight oval.
  ///
  /// A size change is not a licence to re-derive the layout. Keep this table,
  /// keep [_kRingHeight], and make the type change fit inside them — if it will
  /// not fit, the type change is too big. The one knob that genuinely relaxes
  /// the constraint without touching the shape is SHORTER BODY COPY.
  ///
  ///     Report Issue   -0.19  -0.53      Emergency    +0.56  -0.31
  ///     Chat           -0.70  -0.31      Suggestion   +0.72  +0.23
  ///     LGU Updates    -0.76  +0.19      Feedback     +0.28  +0.59
  ///     Events         -0.48  +0.73
  ///
  /// ── What that ruled out ──────────────────────────────────────────────────
  /// A previous pass put three items down each side (Chat, LGU Updates, Events
  /// on the left) in a 700px ring — 454px of free space for 738px of content.
  /// No choice of slots could have worked, and the render proved it: Chat's
  /// body ran under the LGU Updates megaphone, Emergency's under the Suggestion
  /// disc. Pushing the slots apart only moved which pair collided.
  ///
  /// So the ring carries TWO items per side. Events and Feedback are not a
  /// third tier — they sit LOW AND INBOARD, near the vertical axis under the
  /// devices, where they stack against nothing.
  ///
  /// ── The two things the mockup's own arrangement fixes ───────────────────
  /// DEAD SPACE TOP-RIGHT. An earlier table pinned Report Issue at -1.00 and
  /// dropped Emergency to -0.34 — a diagonal hole across the whole upper right
  /// of the section. In the design Report Issue (-0.53) and the two shoulders
  /// (-0.31) are close in height, and Emergency is INBOARD at +0.56 rather than
  /// pinned to the edge. Those two together close the corner.
  ///
  /// ASYMMETRY IS DELIBERATE. Emergency sits further in than Chat, and Feedback
  /// higher than Events, because the device pair leans right and up. Mirroring
  /// the sides is what opened the hole in the first place.
  ///
  /// Order matches [LandingFeatures.features].
  static const List<({Alignment at, TextAlign align})> _kSlots = [
    // Report Issue — high, just left of the axis, clearing the phones' tops.
    //
    // -0.10, not the -0.26 it was. The bottom of the ring is carried by Events
    // (-0.58) and Feedback (+0.28), whose midpoint is -0.15; at -0.26 the top
    // label hung further left than the pair below it and the whole composition
    // leaned left against a device pair that leans RIGHT.
    //
    // It cannot go to centre: the constraint here is horizontal, because Report
    // Issue and Emergency (+0.59) sit at almost the same height (-0.83 against
    // -0.63) and their boxes overlap vertically. -0.10 keeps 0.69 of Alignment
    // between them, which at the tightest band is the whole measure plus room.
    (at: Alignment(-0.10, -0.83), align: TextAlign.center),
    // Chat with Agent — upper-left shoulder.
    (at: Alignment(-0.83, -0.61), align: TextAlign.right),
    // LGU Updates — lower-left, the left side's widest point.
    (at: Alignment(-0.90, 0.02), align: TextAlign.right),
    // Emergency — upper-right shoulder. INBOARD of Chat, not mirroring it:
    // this is what closes the top-right corner.
    (at: Alignment(0.59, -0.63), align: TextAlign.left),
    // Suggestion — lower-right, the right side's widest point.
    (at: Alignment(0.79, 0.02), align: TextAlign.left),
    // Events and Activities — bottom, left of the axis.
    (at: Alignment(-0.58, 0.68), align: TextAlign.center),
    // Feedback — bottom, right of the axis and a little HIGHER than Events.
    (at: Alignment(0.28, 0.70), align: TextAlign.center),
  ];

  /// Height of the ring, which a [Stack] cannot derive from absolutely
  /// positioned children.
  ///
  /// This is an OUTPUT of the slot solve in [_kSlots], not an independent
  /// choice: it is the smallest height at which all 21 label pairs are disjoint
  /// while the ring still holds the mockup's proportions. It also clears the
  /// device box, which at [_kPhoneWidth] and [_FeaturePhone]'s 0.88 aspect is
  /// ~534px tall.
  ///
  /// Lowering it re-opens collisions — silently, because a [Stack] just paints
  /// one label over another. test/landing_features_ring_test.dart is the guard;
  /// run it after touching this, [_kSlots], or [_FeatureItem]'s measure.
  ///
  /// ── This is the SOLVE height, not the height that gets painted ──────────
  /// It is the canvas the slot fractions are interpreted against, and it must
  /// stay 1050 or every slot moves. But the ring never DRAWS to its edges: the
  /// topmost slot is -0.83 and the lowest +0.70, and [Align] centres a child at
  /// its fraction of the FREE space, so the outermost labels stop well short of
  /// the container. Measured, that left 71px unpainted at the top and 128px at
  /// the bottom — a ~200px band of white inside the section at every desktop
  /// width, which read as a broken gap above the next section.
  ///
  /// [_trimTop] and [_trimBottom] take that band back off the painted box
  /// WITHOUT touching the solve. See them for why the two differ.
  static const double _kRingHeight = 1050;

  /// The unpainted margin above the highest label and below the lowest, as a
  /// fraction of [_kRingHeight].
  ///
  /// ── Why these are constants and not a measurement ───────────────────────
  /// The honest version of this would measure the children's real extents and
  /// size the box to them. A [Stack] cannot: its size is decided BEFORE its
  /// non-positioned children are laid out, so there is no legal point at which
  /// to ask "how tall did the labels turn out?" and use the answer. Doing it
  /// properly means a custom RenderBox or a two-pass layout, which is a large
  /// amount of machinery for a number that only changes when the slot table
  /// does — and the slot table carries a standing instruction not to change.
  ///
  /// So they are derived from the table by hand and guarded by a test.
  /// landing_features_ring_test.dart asserts the painted box stays close to the
  /// content's true extent, so if a slot or the measure ever moves, the trim is
  /// wrong and the suite says so rather than silently reopening the gap.
  ///
  /// They are NOT equal, because the ring is not vertically symmetric: the top
  /// slot sits at -0.83 and the bottom at +0.70, so there is more slack below
  /// than above. Measured at 1280+: 74px unpainted above, 134 below.
  static const double _trimTop = 0.055;
  static const double _trimBottom = 0.105;

  /// Width of the device pair at the ring's NARROWEST band — see [_scale].
  ///
  /// This is the width of the PAIR's box, not of one device: the two overlap
  /// inside it at 0.46 each (see [_FeaturePhone]), so a single phone renders
  /// about 235px wide.
  ///
  /// 420, not the 470 it was: at 470 the Emergency label's third line painted
  /// over the splash screen's bezel. The Feedback slot in [_kSlots] was moved
  /// down to +0.70 for the same reason — it was the one label sitting close
  /// enough to the ring's centre to collide with the artwork whatever size the
  /// phone was.
  static const double _kPhoneWidth = 420;

  /// How far the phone yields when the band is narrower than the solve band.
  ///
  /// ── Why the PHONE, and not the labels ───────────────────────────────────
  /// Running the ring below [_kSolvedBand] was measured before it was allowed.
  /// The result is not what the collision arithmetic above would suggest:
  ///
  ///     band   worst label-vs-label     labels ON the device art
  ///     1132   none                     Events 27x20
  ///     1069   none                     Emergency 33x27, Events 45x20
  ///      950   none                     Emergency 68x27, Events 80x20
  ///      900   none                     Emergency 83x27, Suggestion 19x216
  ///      860   Report/Emergency 8x133   four labels on the art
  ///
  /// Label pairs stay disjoint all the way down to 900 — the slot table is in
  /// fractions, so it contracts on its own. What fails first is labels landing
  /// on the ARTWORK, because the phone is the one thing in the ring that was
  /// NOT a fraction: at a fixed 420 it holds its size while the ring closes in
  /// around it.
  ///
  /// So the phone is what gives. Shrinking the labels instead would mean
  /// re-solving the measure, which re-wraps every body and re-opens the
  /// collisions the slot table exists to avoid — the exact failure the warning
  /// on [_kSlots] describes.
  ///
  /// 0.72 is the floor: at the narrowest band the ring now serves, that is the
  /// phone size at which Emergency and Events clear the artwork. Below it the
  /// devices get too small to read as the product.
  static const double _kPhoneFloor = 0.72;

  /// The band the slot table was solved against: an [LandingUi.tabletBreak]
  /// viewport minus a gutter each side.
  ///
  /// ── Why the gutter matters ──────────────────────────────────────────────
  /// The solve originally used 1180 — [LandingUi.contentBand] — and produced a
  /// table that collided at exactly one width: 1180. At that viewport the band
  /// is NOT 1180, because [LandingBand] applies its horizontal padding before
  /// the maxWidth clamp, so the ring gets 1180 - 2*24 = 1132. Every wider
  /// viewport passed, because there the clamp wins and the band really is 1180.
  ///
  /// A layout solved against the wrong width is wrong only in the one place
  /// where the assumption breaks, which is exactly the place least likely to be
  /// spot-checked.
  static const double _kSolvedBand =
      LandingUi.tabletBreak - LandingUi.gutter * 2;

  /// How much to scale the whole composition for the band it actually has.
  ///
  /// The slots in [_kSlots] are fractions, so they reflow on their own — but
  /// the ring HEIGHT, the phone, and the labels are pixel sizes, and left fixed
  /// they make the section shrink into the middle of a wide desktop: the same
  /// 1050px ring in a 1180px band and in a 1600px one.
  ///
  /// Clamped at both ends. Above 1.15 the devices start to overpower the
  /// labels and the composition stops looking like the mockup, so very wide
  /// screens get margin rather than ever-larger artwork.
  ///
  /// The floor is 1.0 and must STAY 1.0 even though the ring now runs below the
  /// solve band. Scaling the labels down with the band is the obvious move and
  /// the wrong one: it shrinks the measure, which re-wraps every body to more
  /// lines, which makes the items TALLER — so the ring gets tighter vertically
  /// exactly as it gets tighter horizontally. The narrow band is absorbed by
  /// [_phoneScale] instead, which is what the collision data says is actually
  /// in the way.
  static double _scale(double bandWidth) =>
      (bandWidth / _kSolvedBand).clamp(1.0, 1.15);

  /// The phone's own scale, which unlike [_scale] DOES fall below 1.
  ///
  /// Above the solve band it simply tracks [_scale], so a desktop is unchanged.
  /// Below it the phone contracts faster than the band does, opening the centre
  /// of the ring so the labels closing in have somewhere to land — see the
  /// measured table on [_kPhoneFloor] for why this is the piece that yields.
  static double _phoneScale(double bandWidth) {
    if (bandWidth >= _kSolvedBand) return _scale(bandWidth);
    return (bandWidth / _kSolvedBand).clamp(_kPhoneFloor, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder, not MediaQuery: what matters is the width this widget was
    // actually GIVEN — after the page gutter and the content-band clamp — not
    // the width of the window. Those differ by 48px at the one breakpoint where
    // the ring is tightest, which is precisely where a mistake shows up.
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = _scale(constraints.maxWidth);
        final phoneScale = _phoneScale(constraints.maxWidth);

        // ── Solve height inside, painted height outside ────────────────────
        // The Stack keeps the FULL [_kRingHeight], because that is the canvas
        // the slot fractions are measured against — shrink it and every label
        // moves, which is the re-solve the table forbids.
        //
        // What shrinks is the box the section reserves in the page. OverflowBox
        // lets the taller Stack lay out at its solve height inside a shorter
        // parent, and the alignment picks which part of it lands where: the
        // trims are asymmetric, so the Stack is pulled UP by the difference
        // between them, putting the painted content in the middle of the box
        // rather than the geometric centre of the solve canvas.
        final solved = _kRingHeight * scale;
        final painted = solved * (1 - _trimTop - _trimBottom);
        // -1 puts the Stack's top at the box's top, +1 its bottom at the
        // bottom; this places it so exactly _trimTop of the canvas is above the
        // box and _trimBottom below.
        final pull = (_trimTop - _trimBottom) / (_trimTop + _trimBottom);

        return SizedBox(
          height: painted,
          child: OverflowBox(
            minHeight: solved,
            maxHeight: solved,
            alignment: Alignment(0, pull),
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // The devices, centred and behind the labels.
                RevealOnScroll(
                  delay: const Duration(milliseconds: 140),
                  offset: 32,
                  child: SizedBox(
                    width: _kPhoneWidth * phoneScale,
                    child: const _FeaturePhone(),
                  ),
                ),
                for (final (i, slot) in _kSlots.indexed)
                  Align(
                    alignment: slot.at,
                    child: RevealOnScroll(
                      // Staggered clockwise from the top, so the ring assembles
                      // around the devices rather than all at once.
                      delay: Duration(milliseconds: 70 * i),
                      child: _FeatureItem(
                        feature: LandingFeatures.features[i],
                        align: slot.align,
                        scale: scale,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The narrow composition: the phone, then the six as cards.
class _FeatureGrid extends StatelessWidget {
  final bool narrow;
  const _FeatureGrid({required this.narrow});

  @override
  Widget build(BuildContext context) {
    // Columns are chosen by the width actually AVAILABLE, not by the page's
    // `narrow` flag.
    //
    // `narrow` is "< 900", which is the breakpoint the HERO needs — its
    // two-column text-and-art layout stops working there. Reusing it here put a
    // portrait tablet (834px) into a single column of very wide, very short
    // cards with empty space either side, when it comfortably fits two.
    //
    // ── The two-up reaches down to a large phone ────────────────────────────
    // The floor was 560, which put a 535px window — a landscape handset, or a
    // narrow desktop window — into ONE column of very wide, very short cards.
    // Seven of those is a long scroll of banners, and the section stops reading
    // as a set of features.
    //
    // 460 instead. At that width a card is ~215px, which still holds the
    // longest body ("Quick access to hotlines and emergency services when you
    // need them.") without the one-word-per-line rag that makes a narrow tile
    // unreadable — the cards get taller, not broken, and the rows now match
    // heights so a taller card no longer leaves a ragged edge.
    //
    // Below 460 it is genuinely one column: a ~190px card wraps the same body
    // past five lines and the pair is worse than the single.
    //
    // ── Why THREE columns in the band just under the ring ───────────────────
    // Two-up ran all the way from 560 to the ring break, so an 850-930px window
    // got the same layout a 600px tablet does — only with each card stretched
    // wider. At that width a card is ~430px holding one line of body text, so
    // the tile is far wider than it is tall and the section reads as a stack of
    // banners rather than as a set of features. It also puts SEVEN items into
    // four rows, leaving the last row half empty.
    //
    // 820 is where a third column becomes readable: it gives ~250px a card,
    // which still holds the longest body ("Quick access to hotlines and
    // emergency services when you need them.") in four lines without the
    // one-word-per-line rag that a narrower tile produces.
    //
    // Below 820 the two-up is kept exactly as it was — that is the 2x2 that
    // works on a phone and a small tablet, and this change does not touch it.
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 820
        ? 3
        : width >= 460
        ? 2
        : 1;

    return Column(
      children: [
        // ── The device pair, sized CONTINUOUSLY ──────────────────────────────
        // This used to be `narrow ? 250 : 330`, which is a single step at the
        // 900px hero breakpoint and then a flat 330 all the way to 1180. The
        // result was a phone that looked right on a handset, jumped, and then
        // shrank steadily relative to the page across the whole tablet range —
        // most visible at 1100, just before the ring takes over at 1180.
        //
        // A fraction of the available width instead, so the artwork holds the
        // same share of the page at every size in between. Clamped at both ends:
        // below 240 the in-app UI on the screens stops being legible, and above
        // 380 the pair dominates a tablet that still has to show seven cards
        // under it.
        LayoutBuilder(
          builder: (context, constraints) {
            // The upper clamp is 460, not the 380 it was. 380 was reached at
            // ~905px and then held flat, so across the whole top of the grid's
            // range the artwork stopped growing while the page kept widening —
            // the phone shrank RELATIVE to the page and ended up a small object
            // marooned in white with the cards pushed below the fold. Now that
            // the ring takes over at 940 the grid's top end is 939, and 460
            // keeps the art in proportion right up to it.
            final phoneWidth = (constraints.maxWidth * 0.42).clamp(
              240.0,
              460.0,
            );
            return RevealOnScroll(
              offset: 32,
              child: SizedBox(width: phoneWidth, child: const _FeaturePhone()),
            );
          },
        ),
        const SizedBox(height: 44),
        // ── Explicit ROWS, not a Wrap ────────────────────────────────────────
        // A Wrap was the obvious structure and it produced the defect: it gives
        // every child its natural height, so cards sitting side by side ended
        // at different depths. The bodies are different lengths — "Easily
        // report problems in your area and track their status." is two lines
        // where "Get instant assistance and answers from authorized LGU staff."
        // is three — so each row had a ragged bottom edge and the grid read as
        // a pile of loose tiles rather than a set.
        //
        // Rows of IntrinsicHeight with stretched children instead: every card
        // in a row takes the height of the tallest, which is what makes the
        // grid look like a grid. IntrinsicHeight is affordable here because a
        // row holds at most three short cards, and it runs once per row rather
        // than over the whole section.
        //
        // Still not a GridView: this is inside a scroll view, so a GridView
        // would need shrinkWrap and its own physics for no benefit, and it
        // cannot give the last row a different span (see below).
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 18.0;
            final cardWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;

            // ── The last row is widened to fill, not left ragged ────────────
            // Seven items never divide evenly into two or three columns, so the
            // final row always runs short: one card and a hole beside it at
            // two-up, one card and TWO holes at three-up. Rendered, that hole
            // reads as a missing card rather than as the end of the list —
            // especially at three-up, where two thirds of the last row is
            // empty white inside a section that is otherwise a tidy block.
            //
            // The remainder cards widen to close it — but only to TWO columns,
            // never three. Letting the single leftover card span all three was
            // the first attempt and it looked worse than the hole: a card three
            // times the width of its neighbours, holding one short line of
            // body, reads as a banner or a call-to-action rather than as the
            // seventh peer in a set. Two columns is wide enough to leave no
            // visible gap at the start of the row and close enough to a normal
            // card to still read as one.
            //
            // The card's content is top-left aligned, so a wider tile simply
            // gives its body a longer measure — nothing stretches.
            const maxSpan = 2;
            final remainder = LandingFeatures.features.length % columns;
            final firstInLastRow = remainder == 0
                ? -1
                : LandingFeatures.features.length - remainder;
            final span = remainder == 0
                ? 1
                : (columns ~/ remainder).clamp(1, maxSpan);
            final lastRowWidth = cardWidth * span + gap * (span - 1);

            final rows = <Widget>[];
            for (
              var start = 0;
              start < LandingFeatures.features.length;
              start += columns
            ) {
              final end = (start + columns).clamp(
                0,
                LandingFeatures.features.length,
              );
              final isLastRow = firstInLastRow >= 0 && start >= firstInLastRow;
              final width = isLastRow ? lastRowWidth : cardWidth;

              rows.add(
                RevealOnScroll(
                  // Staggered by ROW, not by item: cards side by side should
                  // arrive together, or the eye is dragged left-right down the
                  // grid instead of reading it as rows.
                  delay: Duration(milliseconds: 70 * (start ~/ columns)),
                  child: IntrinsicHeight(
                    child: Row(
                      // The row is left-packed: a short last row keeps its
                      // cards at the start rather than centring them, so the
                      // grid's left edge stays a straight line all the way
                      // down.
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = start; i < end; i++) ...[
                          if (i > start) const SizedBox(width: gap),
                          SizedBox(
                            width: width,
                            child: _FeatureCard(
                              feature: LandingFeatures.features[i],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
              if (end < LandingFeatures.features.length) {
                rows.add(const SizedBox(height: gap));
              }
            }
            return Column(children: rows);
          },
        ),
      ],
    );
  }
}

/// The floating device at the centre of the section.
class _FeaturePhone extends StatelessWidget {
  const _FeaturePhone();

  @override
  Widget build(BuildContext context) {
    // AspectRatio wrapping the whole Stack: both layers are undecoded images
    // with no intrinsic height, so without this the composition collapsed to
    // zero and the ring's two text columns lost their centre. See _HeroArt in
    // landing_hero.dart.
    //
    // ── TWO devices, as the design draws it ─────────────────────────────────
    // The mockup's centrepiece is a PAIR: a back phone showing the app's Quick
    // Actions list, and in front of it, offset up and to the right, a second
    // showing the green-to-blue splash. The first build used only one, which
    // is why the section read as flatter and emptier than the design.
    //
    // Both are already converted — Phone1 is the list, Phone2 the splash.
    //
    // 0.88, taller than wide. The pair steps UP as it steps right — the
    // vertical separation (0.35 of the box) is larger than the horizontal
    // (0.31) — so the two devices together occupy a box slightly taller than
    // it is wide, and the glow spreads a little past them on each side.
    //
    // This was 1.02 while the devices were splayed left-and-right; a wide box
    // is what gave them room to splay.
    return AspectRatio(
      aspectRatio: 0.88,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // The soft coloured glow, behind both devices.
          //
          // Scaled up, because it is a separate export composed around the
          // phones at a different size. `contain` inside this box would draw it
          // no bigger than the devices, which reads as a coloured card behind
          // them rather than as light bleeding out from underneath.
          //
          // ── Why the opacity ─────────────────────────────────────────────
          // The exported asset is a VIVID blob — near-fully-saturated cyan and
          // spring green at its core. Drawn as-is it is the loudest thing in
          // the section: a hard teal splash that swallows the phones and pulls
          // the eye off the seven labels, which are what the section is for.
          //
          // The mockup's glow is a pale haze you half-notice — the devices sit
          // on light, not on a colour field. This is that same artwork read at
          // the design's strength. It cannot be fixed by scaling: the blob is
          // the right SHAPE, just far too strong.
          //
          // Scale tracks the pair's own spread: the devices now separate to
          // roughly +/-0.45 of the box where they used to sit near the middle,
          // so a glow that only reached 1.18 stopped short of both of them and
          // read as a puddle BETWEEN two phones rather than as light behind
          // them. 1.34 carries it past both outer edges.
          Positioned.fill(
            child: Opacity(
              opacity: 0.38,
              child: Transform.scale(
                scale: 1.34,
                child: Image.asset(
                  'assets/images/landing/features_glow.webp',
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),

          // BACK: the Quick Actions list, LEFT and LOWER, partly hidden behind
          // the splash device in front of it.
          //
          // ── The overlap, and how to compute it ───────────────────────────
          // This is the pair's whole problem, and it is arithmetic, not taste.
          //
          // BOTH ASSETS ARE CROPPED TO THEIR ALPHA BOUNDING BOX by
          // tool/build_landing_assets.py, so the device fills its frame edge to
          // edge — there is no transparent margin for two boxes to overlap
          // into. Whatever the boxes overlap by, the DEVICES overlap by.
          //
          // Alignment units are not fractions of the box either: `Align` maps
          // -1..1 across the FREE space, `box - child`. A child of widthFactor
          // w at slot `a` has its centre at `0.5 + a * (1 - w) / 2`, so it
          // spans `centre +/- w/2`.
          //
          // Earlier passes ignored both facts and placed two ~0.5-wide children
          // barely 0.2 apart, which overlaps them by well over half a device.
          // The splash phone paints second, so it simply covered the Quick
          // Actions list: the render showed one fused shape with no readable
          // content behind it.
          //
          // ── The pair is a STEEP DIAGONAL, not a splay ────────────────────
          // Measured off the mockup, as fractions of this box:
          //
          //     list   centre (-0.21, +0.11)   width 0.26
          //     splash centre (+0.10, -0.24)   width 0.27
          //
          // The separation is dx 0.31, dy 0.35 — THE VERTICAL STEP IS THE
          // LARGER OF THE TWO. That is what makes the design's pair read as one
          // object: two near-parallel devices stacked up-and-right, the splash
          // phone overlapping the list phone's upper right.
          //
          // Every previous pass had that ratio backwards. Slots of -0.72/+0.54
          // put 1.26 of Alignment between the two horizontally against 0.68
          // vertically — four times the design's horizontal separation and a
          // shallower step. Rendered, the devices leaned away from each other
          // from a single touching corner: a V with a wedge of background
          // through the middle, which is exactly what it looked like.
          //
          // ── How much they overlap, measured rather than judged ───────────
          // The reliable way to state this is where the SPLASH PHONE'S LEFT
          // EDGE falls across the list phone, because that is what decides how
          // much of the Quick Actions screen a reader can still see.
          //
          //     mockup   54-55% across the list phone   (its right half only)
          //
          // These slots put it at 54%. Earlier passes sat at 42%, which buried
          // the news cards and most of the Quick Action rows.
          //
          // ── The trap: overlap is a RATIO, not a separation ───────────────
          // The pass before this one widened the gap between the two slots and
          // the overlap got WORSE, which looks impossible until you measure the
          // devices against the pair they form:
          //
          //     mockup   one device = 60% of the pair's total span
          //     that pass  one device = 71% of the pair's total span
          //
          // Phones drawn that large relative to their separation cannot help
          // overlapping heavily — pushing them apart widens the pair and the
          // ratio barely moves. The fix is a SMALLER widthFactor together with
          // a wider separation, which is what 0.46 at ∓0.46 is. It yields 46%
          // of a device overlapped, against the mockup's 45%.
          //
          // Both failure directions have been on screen: too little overlap
          // splayed the pair into a V with background showing through, too much
          // buried the list phone behind the splash screen.
          //
          // Lower than the front device by design: the mockup steps them, so
          // the splash phone's top clears the list phone's and the pair reads
          // as a diagonal rather than as two objects on a shelf.
          //
          // ── Why there is no rotation ─────────────────────────────────────
          // A -0.10rad lean was added here once to give the pair "depth".
          // Rendered, it did the opposite: the artwork ALREADY carries its own
          // perspective, so rotating it again tipped the device off-axis and
          // the pair read as two slabs dropped on the page at angles.
          Align(
            alignment: const Alignment(-0.46, 0.31),
            child: FractionallySizedBox(
              widthFactor: 0.46,
              child: Image.asset(
                'assets/images/landing/features_phone_front.webp',
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),

          // FRONT: the splash screen, RIGHT and HIGHER, overlapping the back
          // device's right edge.
          //
          // Lifted above the back device (-0.31 against +0.31). That step is
          // the composition: it is what puts the splash screen over the list
          // phone's upper right rather than beside it.
          //
          // The size of the step is measured, not chosen. In the mockup the two
          // device centres are 0.169 of the composition apart vertically and
          // 0.138 apart horizontally — the VERTICAL separation is the larger of
          // the two, which is what makes the pair read as one object stacking
          // up-and-right instead of two phones side by side.
          //
          // ── The extra lean ───────────────────────────────────────────────
          // The two devices in the mockup are NOT at the same angle. Measuring
          // each silhouette's long edge against vertical: the list phone leans
          // ~5.1 degrees, the splash phone ~8.8 — a difference of about 3.7,
          // which is 0.065 radians.
          //
          // That small difference is load-bearing. Both assets already carry
          // their own baked-in perspective, so the ONLY thing this rotation adds
          // is the relative lean between them, and it is what stops the pair
          // reading as two copies of one object at one angle.
          //
          // Kept small deliberately. An earlier attempt at "depth" here used
          // -0.10 rad on the OTHER device and tipped it visibly off-axis, so the
          // pair looked like two slabs dropped on the page. Rotating the artwork
          // much beyond its own perspective always looks wrong.
          //
          // The rotation sits INSIDE the Align, wrapping the image itself.
          // Outside it, `Transform.rotate` would spin the whole positioning
          // layer about the Stack's centre, which swings the phone along an arc
          // and moves it off its measured slot — the lean would come with an
          // unasked-for translation.
          Align(
            alignment: const Alignment(0.46, -0.42),
            child: FractionallySizedBox(
              widthFactor: 0.46,
              child: Transform.rotate(
                angle: 0.065,
                child: Image.asset(
                  'assets/images/landing/features_phone_back.webp',
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One feature in the RING: icon above, then title and body, aligned toward the
/// device in the middle.
class _FeatureItem extends StatelessWidget {
  final LandingFeature feature;

  /// How this item's text is justified — right for items on the left of the
  /// ring, left for items on the right, centre for the two at top and bottom.
  /// Set from the item's slot; see [_FeatureRing._kSlots].
  final TextAlign align;

  /// Uniform scale for the whole item, from [_FeatureRing._scale].
  ///
  /// Applied to the MEASURE as well as to the type. Scaling the type alone
  /// would add wrapped lines at larger sizes and silently re-open the ring's
  /// collisions — the measure and the font size are one constraint here.
  final double scale;

  const _FeatureItem({
    required this.feature,
    required this.align,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    // The icon sits centred over its own label, as the mockup draws it, while
    // the TEXT justifies toward the outside of the ring.
    final cross = switch (align) {
      TextAlign.right => CrossAxisAlignment.end,
      TextAlign.left => CrossAxisAlignment.start,
      _ => CrossAxisAlignment.center,
    };

    // ── Sized up SLIGHTLY ──────────────────────────────────────────────────
    // 16/14 against a 62px disc, from 15.5/13.5 against 58. The ring had been
    // the smallest type in its own section — below the [LandingSubhead]
    // directly above it (15.5) — which made it read as a diagram of captions
    // rather than as the seven things the product does.
    //
    // A SLIGHT bump is the whole intent. A previous pass went to 17/15 and then
    // re-solved [_FeatureRing._kSlots] and [_FeatureRing._kRingHeight] to make
    // room; the ring lost its shape completely. See the warning on _kSlots.
    //
    // ── The measure is a HEIGHT control, not just a width one ──────────────
    // The measure decides how many lines each body wraps to, which decides the
    // item's height, which decides how far apart [_FeatureRing._kSlots] must
    // place two items on the same side. So it moves WITH the type: 214 is what
    // keeps the tallest item at 239px, inside what the slot table allows.
    //
    // Do not change either number alone, and re-run
    // test/landing_features_ring_test.dart after touching them: the failure
    // mode is silent overlap, which no other check reports.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 214 * scale),
      child: Column(
        crossAxisAlignment: cross,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FeatureIcon(feature: feature, size: 62 * scale),
          SizedBox(height: 14 * scale),
          Text(
            feature.title,
            textAlign: align,
            style: TextStyle(
              fontSize: 16 * scale,
              fontWeight: FontWeight.w700,
              color: LandingUi.textPrimary,
            ),
          ),
          SizedBox(height: 7 * scale),
          Text(
            feature.body,
            textAlign: align,
            style: TextStyle(
              fontSize: 14 * scale,
              height: 1.55,
              color: LandingUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// One feature as a CARD, for the narrow grid.
class _FeatureCard extends StatelessWidget {
  final LandingFeature feature;
  const _FeatureCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: LandingUi.surface,
        borderRadius: BorderRadius.circular(LandingUi.cardRadius),
        border: Border.all(color: const Color(0xFFE6EBF2)),
        boxShadow: LandingUi.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FeatureIcon(feature: feature, size: _FeatureIcon.kCardSize),
          const SizedBox(height: 14),
          Text(
            feature.title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: LandingUi.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          // 14.5, not the ring's 15: a card is a fixed frame and its copy has
          // to sit inside a border, where the ring's floats on open page.
          Text(
            feature.body,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.55,
              color: LandingUi.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The tinted disc carrying one feature's glyph.
class _FeatureIcon extends StatelessWidget {
  final LandingFeature feature;

  /// Diameter.
  ///
  /// The ring passes `62 * scale` — 62 rather than the 58 it was, because at 58
  /// the disc was smaller than the type it introduced was tall, and against the
  /// phone pair the whole ring read as a diagram of small captions.
  final double size;

  const _FeatureIcon({required this.feature, required this.size});

  /// In the narrow grid, where each disc heads a card rather than floating on
  /// the page. Smaller than the ring's because a card is a much tighter frame,
  /// and a 68px disc inside a phone-width card crowds the copy under it.
  static const double kCardSize = 60;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: feature.tint, shape: BoxShape.circle),
      // Padding scales with the disc so the glyph keeps the same optical
      // weight at both sizes — a fixed inset would make the larger disc read
      // as a small glyph adrift in a big circle.
      padding: EdgeInsets.all(size * 0.22),
      child: Image.asset(
        feature.asset,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

class LandingFeature {
  final String asset;
  final Color tint;
  final String title;
  final String body;

  const LandingFeature({
    required this.asset,
    required this.tint,
    required this.title,
    required this.body,
  });
}
