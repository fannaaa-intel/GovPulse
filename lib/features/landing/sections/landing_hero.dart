import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../landing_page.dart' show LandingBand;
import '../landing_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/reveal_on_scroll.dart';

/// The hero: headline, supporting line, store badges, device art, trust strip.
///
/// ── The background is PAINTED, not loaded ──────────────────────────────────
/// The design's hero sits on a 1920x1080 PNG that is nothing but a soft blue
/// gradient with dither noise — 6 MB, and the single largest asset in the
/// original set, because PNG cannot compress noise. [LandingUi.heroWash]
/// reproduces it from colours sampled out of that very file, for no bytes at
/// all. See tool/build_landing_assets.py, which deliberately skips it.
///
/// ── Entrance ───────────────────────────────────────────────────────────────
/// The hero animates on LOAD rather than on scroll, because it is already in
/// view. That falls out of [RevealOnScroll] rather than needing its own path:
/// the first visibility check runs in a post-frame callback, so anything on
/// screen at first paint starts immediately. The copy leads and the art follows
/// 120ms later, so the eye is given the headline before the picture.
class LandingHero extends StatelessWidget {
  const LandingHero({super.key});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.mobileBreak;

    return LandingBand(
      gradient: LandingUi.heroWash,
      // Bottom padding was 0, which pinned the trust strip to the very edge of
      // the hero's wash — its subtitles sat ON the boundary and the whole strip
      // read as cut off rather than as the foot of the section.
      padding: EdgeInsets.fromLTRB(
        LandingUi.gutter,
        narrow ? 36 : 56,
        LandingUi.gutter,
        narrow ? 28 : 36,
      ),
      child: Column(
        children: [
          if (narrow)
            const Column(
              children: [
                RevealOnScroll(child: _HeroCopy()),
                SizedBox(height: 36),
                RevealOnScroll(
                  delay: Duration(milliseconds: 120),
                  child: _HeroArt(),
                ),
              ],
            )
          else
            const Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: RevealOnScroll(child: _HeroCopy())),
                SizedBox(width: 32),
                Expanded(
                  flex: 6,
                  child: RevealOnScroll(
                    delay: Duration(milliseconds: 120),
                    child: _HeroArt(),
                  ),
                ),
              ],
            ),
          SizedBox(height: narrow ? 40 : 56),
          const RevealOnScroll(
            delay: Duration(milliseconds: 220),
            child: _TrustStrip(),
          ),
        ],
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.mobileBreak;
    final align = narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = narrow ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: align,
      children: [
        Text.rich(
          const TextSpan(
            children: <TextSpan>[
              TextSpan(text: 'Stronger Community,\n'),
              TextSpan(
                text: 'Better ',
                style: TextStyle(color: LandingUi.accentGreen),
              ),
              TextSpan(
                text: 'Governance',
                style: TextStyle(color: LandingUi.accentBright),
              ),
            ],
          ),
          textAlign: textAlign,
          style: TextStyle(
            fontSize: narrow ? 34 : 48,
            height: 1.14,
            fontWeight: FontWeight.w800,
            color: LandingUi.textPrimary,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'GovPulse is your all-in-one platform to stay informed, report '
            'issues, access LGU updates, and help build a better community.',
            textAlign: textAlign,
            style: const TextStyle(
              fontSize: 16,
              height: 1.65,
              color: LandingUi.textBody,
            ),
          ),
        ),
        const SizedBox(height: 28),

        // The primary actions come FIRST and the store badges after, which is
        // the reverse of the mockup's emphasis and deliberate: the web app
        // works today and the store listings do not exist yet, so the thing
        // that actually gets a citizen in has to be the thing they reach first.
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
          children: [
            FilledButton(
              onPressed: () => context.go('/signup'),
              style: FilledButton.styleFrom(
                backgroundColor: LandingUi.ctaGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LandingUi.controlRadius),
                ),
              ),
              child: const Text(
                'Get Started',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
            ),
            OutlinedButton(
              // The guest path. Kept prominent: someone deciding whether this
              // is worth an account should be able to see the community feed
              // before making one.
              onPressed: () => context.go('/guest'),
              style: OutlinedButton.styleFrom(
                foregroundColor: LandingUi.textPrimary,
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(LandingUi.controlRadius),
                ),
              ),
              child: const Text(
                'Browse as guest',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          'Download the app',
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: LandingUi.textPrimary,
          ),
          textAlign: textAlign,
        ),
        const SizedBox(height: 12),
        StoreBadges(
          alignment: narrow ? WrapAlignment.center : WrapAlignment.start,
        ),
      ],
    );
  }
}

/// The phone-and-laptop composition.
class _HeroArt extends StatelessWidget {
  const _HeroArt();

  @override
  Widget build(BuildContext context) {
    // AspectRatio around the image, NOT just `fit: contain`.
    //
    // ── The bug this fixes ────────────────────────────────────────────────
    // An `Image.asset` has NO intrinsic size until its bytes have decoded, and
    // decoding is asynchronous. Inside an Expanded with an unbounded height —
    // which is what a Row in a scroll view gives it — that means the image
    // lays out at HEIGHT ZERO on the first frames.
    //
    // Measured: 626.2 x 0.0. And because the hero Row is centre-aligned, a
    // zero-height sibling drags the whole row's height down with it, so the
    // headline, the buttons and the badges beside it collapsed too. In the
    // browser, where decode is slower than in a widget test, the hero rendered
    // as an empty blue band — which is exactly how it looked in the first real
    // screenshot, and why forcing reduced-motion changed nothing: the
    // animations were never the problem.
    //
    // AspectRatio gives the box a height derived from its width immediately,
    // so the row has its full geometry on frame one and the image simply fades
    // into a space that was already the right shape. 1.77 is the asset's own
    // ratio after the build script crops its transparent margin away
    // (1600x904) — see tool/build_landing_assets.py. Before that crop the file
    // was a 1800x1800 square that was 62% empty, which both blurred the edges
    // and forced this box to reserve a tall square for a wide subject.
    return AspectRatio(
      aspectRatio: 1600 / 904,
      child: Image.asset(
        'assets/images/landing/hero_devices.webp',
        fit: BoxFit.contain,
        // Decorative: the headline beside it already says what the product is,
        // and "phone and laptop showing the GovPulse app" adds nothing a screen
        // reader user needs.
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// The strip under the hero.
///
/// ── Why these are claims and not metrics ───────────────────────────────────
/// The approved design puts four figures here — "3.5+ Active Users", "2K
/// Transaction", "1.5K Downloads", "4.9/5 App Rating". None of them can be
/// substantiated: GovPulse is not published to either app store yet, so there
/// are no downloads and no rating to report, and inventing them on the front
/// page of a GOVERNMENT platform is not a marketing liberty — it is a false
/// statement to citizens, and the first one a journalist or an opposing
/// councillor would check.
///
/// So the strip keeps its visual job — four short proof points across the foot
/// of the hero — and states only things that are true today. When the app is
/// live and the numbers are real, this is the one widget to change.
class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  /// The four proof points.
  ///
  /// ── No icons, by request and by design ──────────────────────────────────
  /// The mockup's strip is type only — a bold figure over a small grey label,
  /// separated by hairline rules. The icons that used to head each column are
  /// gone: at 26px they added colour and weight to a band whose whole job is to
  /// be quiet under the hero, and the design does not have them.
  ///
  /// `accent` is the short suffix the mockup sets in blue after each figure —
  /// its "+" and "★". Null where the claim does not take one.
  static const List<({String figure, String accent, String label})> _items = [
    (figure: 'Verified', accent: '', label: 'Identity-checked accounts'),
    (figure: 'Free', accent: '', label: 'No cost for residents'),
    (figure: '24/7', accent: '', label: 'Emergency hotlines'),
    (figure: 'Official', accent: '', label: 'Run by LGU Aparri'),
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.mobileBreak;

    return Container(
      padding: EdgeInsets.symmetric(vertical: narrow ? 24 : 30, horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1A0F172A))),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        runSpacing: 24,
        // No horizontal spacing: the DIVIDERS below provide the gap, as the
        // mockup draws it. A Wrap `spacing` here would double it and leave the
        // rules floating away from the columns they separate.
        spacing: 0,
        children: [
          for (final (i, item) in _items.indexed) ...[
            // A hairline rule between columns — not after the last, and not
            // before the first. On a phone the strip wraps to two rows, so the
            // rule before index 2 would land at the START of the second row;
            // dropping it there keeps each row reading as its own pair.
            if (i > 0 && !(narrow && i == 2))
              Container(
                width: 1,
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                color: const Color(0x1A0F172A),
              ),
            SizedBox(
              // Two-up on a phone, four-up above the break. A fixed width
              // rather than Expanded because this is a Wrap, which has no flex.
              width: narrow ? 140 : 200,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The figure, with its blue suffix on the same line. A
                  // RichText rather than a Row so the two parts share one
                  // baseline — a Row would align their BOXES, and the smaller
                  // accent would sit visibly low against the large figure.
                  Text.rich(
                    TextSpan(
                      text: item.figure,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: LandingUi.textPrimary,
                        height: 1.1,
                      ),
                      children: [
                        if (item.accent.isNotEmpty)
                          TextSpan(
                            text: ' ${item.accent}',
                            style: const TextStyle(
                              color: LandingUi.accentBright,
                            ),
                          ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: LandingUi.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
