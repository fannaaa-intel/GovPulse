import 'package:flutter/material.dart';

import '../landing_page.dart'
    show LandingBand, LandingEyebrow, LandingHeading, LandingSubhead;
import '../landing_theme.dart';
import '../widgets/reveal_on_scroll.dart';

/// The three steps, alternating art and copy left/right down the page.
///
/// ── Why the alternation is dropped when narrow ─────────────────────────────
/// On a wide screen the zig-zag is what gives the section its rhythm and makes
/// three similar blocks read as a sequence. Stacked into one column it does the
/// opposite: art-then-text followed by text-then-art reads as an inconsistent
/// layout rather than an intentional one. So below [LandingUi.mobileBreak]
/// every step takes the same shape — art, then copy.
class LandingHowItWorks extends StatelessWidget {
  const LandingHowItWorks({super.key});

  static const List<_Step> _steps = <_Step>[
    _Step(
      asset: 'assets/images/landing/how_signin.webp',
      eyebrow: 'Create an account',
      // Wording taken from the approved design rather than paraphrased.
      title: 'Create/login to an existing account to get started',
      body: 'An account is created with your email and a desired password.',
    ),
    _Step(
      asset: 'assets/images/landing/how_verify.webp',
      eyebrow: 'Verify your account',
      title: 'Confirm your identity and secure your account',
      body:
          'Confirm your account information to securely access GovPulse '
          'services and features.',
    ),
    _Step(
      asset: 'assets/images/landing/how_enjoy.webp',
      eyebrow: 'Access all features',
      title: 'Unlock the full GovPulse experience',
      body:
          'Access announcements, events, reporting tools, and other services '
          'from one platform.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.mobileBreak;

    // ── The wave ─────────────────────────────────────────────────────────────
    // The design runs a blue-to-green ribbon of fine lines diagonally behind
    // this section, sweeping from the upper left down past the second step.
    // It is the section's whole visual identity — without it the three steps
    // sit on flat white and the band reads as unfinished, which is exactly how
    // the first build looked next to the mockup.
    //
    // Painted as a Stack layer rather than a DecorationImage so it can be
    // positioned and sized independently of the content: the artwork is a wide
    // 1080x590 ribbon that has to span the full bleed of the section while the
    // copy stays inside the content band.
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  LandingUi.surface,
                  Color(0xFFF4FAFD),
                  LandingUi.surface,
                ],
              ),
            ),
          ),
        ),
        // ── The ribbon, laid over the STEPS ────────────────────────────────
        // Two passes down the section, because one 590px sweep cannot span a
        // band this tall — but NEITHER is mirrored, and that is the correction.
        //
        // The artwork runs blue at its left edge through to lime at its right.
        // That direction is the design's, and flipping the second copy to
        // "vary" it put green on the left and blue on the right, reversing the
        // brand's own gradient halfway down the section. In the mockup the
        // ribbon reads as one continuous flow — blue behind step 1, greening as
        // it falls past step 3 — which is what two same-facing passes give.
        //
        // The earlier failures are still worth recording, since each looked
        // plausible: pinned to the top it covered steps 1-2 and left step 3 on
        // flat white; pinned to both edges it put ribbon at the ENDS and left
        // the middle bare; centred, it dressed step 2 alone.
        //
        // `IgnorePointer` on both because they are pure decoration and must
        // never intercept a tap meant for the content.
        // The UPPER pass, behind the first step — and the only flipped one.
        Positioned.fill(
          child: Align(
            alignment: const Alignment(0, -0.52),
            child: _WaveLayer(narrow: narrow, flipped: true),
          ),
        ),
        // The LOWER pass, behind the second and third steps, as drawn.
        Positioned.fill(
          child: Align(
            alignment: const Alignment(0, 0.62),
            child: _WaveLayer(narrow: narrow),
          ),
        ),
        LandingBand(
          padding: EdgeInsets.symmetric(
            vertical: narrow ? 64 : 88,
            horizontal: LandingUi.gutter,
          ),
          child: Column(
            children: [
              const RevealOnScroll(child: LandingEyebrow('How it works')),
              const SizedBox(height: 18),
              const RevealOnScroll(
                delay: Duration(milliseconds: 60),
                child: LandingHeading(
                  lead: 'Get Connected in ',
                  highlight: '3 Simple Steps',
                ),
              ),
              const SizedBox(height: 16),
              const RevealOnScroll(
                delay: Duration(milliseconds: 110),
                child: LandingSubhead(
                  'A quick and simple process that gets you connected to your '
                  'community in just a few steps.',
                  maxWidth: 660,
                ),
              ),
              SizedBox(height: narrow ? 44 : 64),
              for (final (index, step) in _steps.indexed) ...[
                _StepRow(
                  step: step,
                  index: index,
                  // Art on the left for even steps, right for odd — the design's
                  // zig-zag. Always art-first when stacked; see the class doc.
                  artFirst: narrow || index.isEven,
                  narrow: narrow,
                ),
                // Tighter than the 72 first used. Rendered at 1440 the steps
                // sat so far apart that only one was ever on screen, and the
                // three stopped reading as a sequence — the mockup runs them
                // close enough that the end of one and the start of the next
                // share the viewport, which is what carries the eye down.
                if (step != _steps.last) const SizedBox(height: 40),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The decorative ribbon that sweeps behind the three steps.
///
/// Scaled taller than its natural `fitWidth` height so that one pass spans the
/// steps rather than sitting as a thin band across them. See its use site for
/// why it is centred rather than pinned to an edge.
class _WaveLayer extends StatelessWidget {
  final bool narrow;

  /// Mirrors the sweep top-to-bottom.
  ///
  /// The band draws this layer TWICE — once high behind the first step, once
  /// low behind the second and third (see the two [Align]s at the use site).
  /// Only the upper one is flipped: its crest otherwise rises into the first
  /// step's heading, while the lower copy already falls away from the copy it
  /// sits behind and reads correctly as drawn.
  ///
  /// Flipping both was the first attempt and it mirrored the whole band, which
  /// is not what the design does — the two passes are deliberately not the same
  /// shape, and that asymmetry is what keeps the ribbon from looking tiled.
  final bool flipped;

  const _WaveLayer({required this.narrow, this.flipped = false});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        // The mockup's ribbon is a pale wash behind the art, not a graphic
        // competing with the copy. Any stronger and the step headings lose
        // contrast where the wave crosses them.
        //
        // 0.62 was still too present once rendered: the green half of the
        // sweep came up as a distinct ribbon running THROUGH the step copy,
        // where the design has it as a barely-there tint you notice only after
        // the words. The artwork's own greens are more saturated than its
        // blues, so the level has to be set by where the ribbon is strongest,
        // not by its average.
        opacity: 0.34,
        child: Transform.scale(
          // Opened out vertically, but only just. The artwork is a wide,
          // shallow sweep (1080x590); at its natural proportions across this
          // band it is a thin ribbon through a single step.
          //
          // 1.9 was far too much — it pulled the curves near-vertical and the
          // ribbon stopped reading as a horizontal flow across the page, which
          // is exactly what the design draws. Even 1.35 visibly steepened the
          // crests. 1.15 reaches the steps while keeping the sweep's own shape.
          //
          // NEGATED when [flipped] — a negative scale is the whole mirror, and
          // it costs nothing extra because the Transform is here regardless.
          // Doing it in the asset instead would mean regenerating a file that
          // tool/build_landing_assets.py owns, and the next run of that script
          // would silently undo it.
          scaleY: (narrow ? 1.35 : 1.15) * (flipped ? -1 : 1),
          child: Image.asset(
            'assets/images/landing/how_background.webp',
            fit: BoxFit.fitWidth,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final _Step step;
  final int index;
  final bool artFirst;
  final bool narrow;

  const _StepRow({
    required this.step,
    required this.index,
    required this.artFirst,
    required this.narrow,
  });

  @override
  Widget build(BuildContext context) {
    final art = _StepArt(asset: step.asset);
    final copy = _StepCopy(step: step, index: index, narrow: narrow);

    if (narrow) {
      return Column(
        children: [
          RevealOnScroll(offset: 28, child: art),
          const SizedBox(height: 24),
          RevealOnScroll(delay: const Duration(milliseconds: 90), child: copy),
        ],
      );
    }

    // The art side leads on the way in, and the copy follows — the same
    // ordering the hero uses, so the whole page has one entrance grammar.
    //
    // 52:48 toward the ART, measured off the mockup. The earlier 45:55 leaned
    // the wrong way: in the design the illustration is unmistakably the larger
    // element — a full-height phone with figures either side — while the copy
    // sits in a narrow column of three or four words a line. Giving the copy
    // the larger share shrank the art below the headline beside it and the two
    // read as equal-weight columns, which is not what the design draws.
    //
    // ── The copy is CENTRED in its slot, not pinned to the outside ──────────
    // [_StepCopy] caps its measure at 360 so the title breaks into the mockup's
    // short stack. But the slot that measure sits in is a flex share of the
    // band, so it KEEPS GROWING: ~360 at 950px, ~500 at 1173, wider still on a
    // desktop. Left to align at the start of that slot, the copy drifted to the
    // page's outer gutter and opened a growing empty channel between itself and
    // the art — the two halves of a row visibly coming apart, worst at the top
    // of the range rather than at the bottom, which is why it survived the
    // narrow sweeps.
    //
    // Centring the block inside its own slot keeps the text the same measure
    // and the same left-aligned rag; it just stops the surplus width all
    // landing on one side of it. The art gets the same treatment implicitly —
    // its AspectRatio already centres within the Expanded.
    final children = <Widget>[
      Expanded(flex: 13, child: RevealOnScroll(offset: 28, child: art)),
      const SizedBox(width: 64),
      Expanded(
        flex: 12,
        child: RevealOnScroll(
          delay: const Duration(milliseconds: 90),
          child: Center(child: copy),
        ),
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: artFirst ? children : children.reversed.toList(),
    );
  }
}

class _StepArt extends StatelessWidget {
  final String asset;
  const _StepArt({required this.asset});

  @override
  Widget build(BuildContext context) {
    // AspectRatio OUTSIDE the image, not merely as an error fallback. An
    // undecoded Image.asset has no intrinsic height, so inside the Expanded
    // this sits in it laid out at zero and took the step's copy column down
    // with it. See the note on _HeroArt in landing_hero.dart.
    //
    // The step art's own ratio after cropping (1400x1375, near-square).
    return AspectRatio(
      aspectRatio: 1400 / 1375,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

class _StepCopy extends StatelessWidget {
  final _Step step;
  final int index;
  final bool narrow;

  const _StepCopy({
    required this.step,
    required this.index,
    required this.narrow,
  });

  /// The copy's measure.
  ///
  /// 360 is the mockup's, and it is what breaks "Create/login to an existing
  /// account to get started" into the short stack the design shows rather than
  /// one long line. It is a CEILING, not a width: the block is centred in its
  /// slot (see [_StepRow]) so a wider slot adds margin either side, never a
  /// longer line.
  ///
  /// It does open out a little on a large desktop, where a frozen 360 next to a
  /// 600px illustration reads as a caption rather than as half of a row — but
  /// only to 420, because past that the title stops breaking into three lines
  /// and the row loses the design's stacked heading.
  static const double _measure = 360;
  static const double _measureWide = 420;

  @override
  Widget build(BuildContext context) {
    final align = narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = narrow ? TextAlign.center : TextAlign.start;

    // The wider measure only above the ring's breakpoint, which is where the
    // slot has actually grown enough to make 360 look mean. Below it the row is
    // tight and the extra 60px would eat the channel between copy and art.
    final wide = MediaQuery.sizeOf(context).width >= LandingUi.tabletBreak;
    final measure = wide ? _measureWide : _measure;

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The eyebrow alone, as the design draws it.
        //
        // A numbered blue circle used to sit in front of this. The mockup has
        // no such badge — just the blue label — and adding one was me improving
        // on the design rather than following it.
        //
        // The ordering is still announced to a screen reader, but through
        // Semantics rather than a drawn glyph: see the label below, which says
        // "Step 1 of 3" without putting anything on screen that the design does
        // not have.
        Semantics(
          label: 'Step ${index + 1} of 3, ${step.eyebrow}',
          excludeSemantics: true,
          child: Text(
            step.eyebrow,
            textAlign: textAlign,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: LandingUi.accentBright,
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Set to the mockup's measure — a tight two- or three-line block, so
        // "Create/login to an existing account to get started" breaks into the
        // short stack the design shows rather than running out as one long
        // line. See [_measure].
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: measure),
          child: Text(
            step.title,
            textAlign: textAlign,
            style: TextStyle(
              // Larger than the 27 first used. In the design this heading is
              // the biggest type on the row by a clear margin — it has to hold
              // its own against a full-height illustration beside it.
              fontSize: narrow ? 24 : 31,
              height: 1.22,
              fontWeight: FontWeight.w800,
              color: LandingUi.textPrimary,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: measure),
          child: Text(
            step.body,
            textAlign: textAlign,
            style: const TextStyle(
              fontSize: 15,
              height: 1.65,
              color: LandingUi.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _Step {
  final String asset;
  final String eyebrow;
  final String title;
  final String body;

  const _Step({
    required this.asset,
    required this.eyebrow,
    required this.title,
    required this.body,
  });
}
