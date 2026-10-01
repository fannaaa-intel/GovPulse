import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:go_router/go_router.dart';

import 'landing_theme.dart';
import 'sections/landing_cta.dart';
import 'sections/landing_faq.dart';
import 'sections/landing_features.dart';
import 'sections/landing_footer.dart';
import 'sections/landing_hero.dart';
import 'sections/landing_how_it_works.dart';
import 'widgets/landing_nav.dart';

// ════════════════════════════════════════════════════════════════════════════
//  THE PUBLIC LANDING PAGE — the front door at the bare origin.
//
//  ── Why this exists ────────────────────────────────────────────────────────
//  Until this page, '/' was not a destination. The router treated it as a
//  placeholder, resolved it to somebody's home the moment auth was known, and
//  mounted a spinner over the gap. Every stranger who typed the origin met a
//  login form demanding credentials for a product nothing had yet explained —
//  backwards for a civic platform, whose whole problem is that the municipality
//  it serves has not heard of it yet.
//
//  ── Structure ──────────────────────────────────────────────────────────────
//  Six sections, each in its own file under `sections/`, in the order of the
//  approved design:
//
//    1. Hero            headline, sub, store badges, device art, trust strip
//    2. Features        the six capabilities, around a phone
//    3. How it works    three steps, alternating left/right
//    4. FAQ             five expandable answers
//    5. CTA             the closing "Start Using GovPulse Today" panel
//    6. Footer          links and contact details
//
//  They are separate files because each is 150-300 lines of layout with its own
//  responsive rules, and a single file carrying all six would be the sort of
//  2000-line widget nobody can safely edit.
//
//  ── Chromeless ─────────────────────────────────────────────────────────────
//  No shell, no citizen nav, no rail. The shell is the SIGNED-IN surface and
//  assumes a session; this is the one screen that may be read by someone with
//  no identity at all. It brings its own Scaffold, exactly as the two consoles
//  do.
//
//  ── Scrolling and anchors ──────────────────────────────────────────────────
//  One [ScrollController] is owned here and handed to the nav, so "Features",
//  "How it Works" and "FAQ" can scroll to their sections. The targets are
//  [GlobalKey]s on the sections themselves rather than hardcoded offsets, which
//  is what keeps the anchors correct when a section's height changes with the
//  viewport — and it changes a lot, because every section restacks under
//  [LandingUi.mobileBreak].
// ════════════════════════════════════════════════════════════════════════════

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final ScrollController _scrollController = ScrollController();

  // Anchor targets for the nav. See the class doc on why these are keys.
  final GlobalKey _featuresKey = GlobalKey();
  final GlobalKey _howKey = GlobalKey();
  final GlobalKey _faqKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Scrolls [key]'s section so its top sits just under the nav.
  ///
  /// The offset is read from the real render tree, so it stays correct no
  /// matter how the sections above have restacked at this width.
  ///
  /// ── Not `Scrollable.ensureVisible(alignment: …)` ─────────────────────────
  /// That aligns a FRACTION of (viewport − section height). For a section
  /// taller than the screen — Features and How it Works on a phone — that
  /// number is negative, so any positive alignment scrolled PAST the section's
  /// top and the eyebrow ("HOW IT WORKS") landed half off-screen. FAQ, short
  /// enough to fit, looked fine, which is why it went unnoticed.
  void _scrollTo(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box == null || !_scrollController.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final position = _scrollController.position;
    // A little air above the section's own top padding.
    const gap = 8.0;
    final target = (viewport.getOffsetToReveal(box, 0).offset - gap).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 640),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LandingUi.surface,
      body: Column(
        children: [
          // The nav sits OUTSIDE the scroll view rather than floating over it.
          // A translucent overlay bar would have to be legible against the
          // hero's sky wash at the top and white cards further down, and the
          // usual fix — fading a background in on scroll — adds a rebuild on
          // every frame of every scroll for very little.
          LandingNav(
            onFeatures: () => _scrollTo(_featuresKey),
            onHowItWorks: () => _scrollTo(_howKey),
            onFaq: () => _scrollTo(_faqKey),
            onGetStarted: () => context.go('/signup'),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LandingHero(),
                  LandingFeatures(key: _featuresKey),
                  LandingHowItWorks(key: _howKey),
                  LandingFaq(key: _faqKey),
                  const LandingCta(),
                  LandingFooter(
                    onFeatures: () => _scrollTo(_featuresKey),
                    onHowItWorks: () => _scrollTo(_howKey),
                    onFaq: () => _scrollTo(_faqKey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centres a section's content in the page band and applies the side gutter.
///
/// Every section uses this, so one can never land on a different measure than
/// its neighbours — the most visible way a landing page looks unfinished.
class LandingBand extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Gradient? gradient;
  final double maxWidth;

  const LandingBand({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      vertical: 88,
      horizontal: LandingUi.gutter,
    ),
    this.background,
    this.gradient,
    this.maxWidth = LandingUi.contentBand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: background, gradient: gradient),
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// The small uppercase label above a section heading, with its underline.
///
/// "FEATURES", "HOW IT WORKS", "FAQ" — a fixed part of the design's section
/// rhythm, so it is one widget rather than three near-copies.
class LandingEyebrow extends StatelessWidget {
  final String label;
  const LandingEyebrow(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: LandingUi.eyebrow,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 34,
          height: 3,
          decoration: BoxDecoration(
            color: LandingUi.eyebrow,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

/// A section heading whose final words are tinted — the design's recurring
/// "Designed for Citizens, **Built for Communities**" treatment.
class LandingHeading extends StatelessWidget {
  /// The part in the default ink.
  final String lead;

  /// The part in [LandingUi.accentBright]. May be empty.
  final String highlight;

  final TextAlign align;

  const LandingHeading({
    super.key,
    required this.lead,
    this.highlight = '',
    this.align = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.mobileBreak;

    return Text.rich(
      TextSpan(
        children: <TextSpan>[
          TextSpan(text: lead),
          if (highlight.isNotEmpty)
            TextSpan(
              text: highlight,
              style: const TextStyle(color: LandingUi.accentBright),
            ),
        ],
      ),
      textAlign: align,
      style: TextStyle(
        fontSize: narrow ? 27 : 36,
        height: 1.22,
        fontWeight: FontWeight.w800,
        color: LandingUi.textPrimary,
        letterSpacing: -0.6,
      ),
    );
  }
}

/// The supporting line under a section heading.
class LandingSubhead extends StatelessWidget {
  final String text;
  final double maxWidth;
  const LandingSubhead(this.text, {super.key, this.maxWidth = 620});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 15.5,
          height: 1.6,
          color: LandingUi.textMuted,
        ),
      ),
    );
  }
}
