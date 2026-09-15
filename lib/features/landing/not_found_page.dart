import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/citizen_ui.dart';
import 'landing_theme.dart';
import 'widgets/brand_mark.dart';

/// The public 404 page, shown by the router's `errorBuilder` for any location
/// that does not match a route.
///
/// ── What this replaces ──────────────────────────────────────────────────────
/// A bare centred `Scaffold` that had two real faults, both visible to the
/// public:
///
///   * it printed `state.error` — a raw framework string — at whoever hit the
///     bad link. That is internal diagnostic text, and a stranger who mistyped
///     a URL should never be shown it.
///   * its only action was "Back to Home", pointing at the signed-in citizen
///     feed. A signed-out visitor — by far the likeliest person to land on a
///     404, since these are the links that get shared and mistyped — cannot
///     reach that route, so the one way out was a dead end for them.
///
/// Both are fixed here: the error string is gone from the UI, and the actions
/// are the landing page and the guest feed, which work signed-in or out.
///
/// ── Why it looks like the landing page ──────────────────────────────────────
/// A 404 is often a stranger's FIRST page — a shared link that rotted, a
/// mistyped address. If it does not look like the product, the visitor's
/// conclusion is that the product is broken. So this reuses the hero's own
/// shape: the sky wash, the two-column split with copy left and artwork right,
/// the green CTA with a white ghost beside it, and the headline whose second
/// line carries colour. Nothing here invents a colour; every value is a
/// [LandingUi] token.
class NotFoundPage extends StatelessWidget {
  /// The location that did not match, e.g. `/my-reprots`.
  ///
  /// Accepted but NOT rendered. The browser's own address bar already shows the
  /// visitor exactly what they typed, in the one place they are used to looking
  /// for it, so repeating it in the page earns nothing — and a monospace path
  /// in the middle of a marketing-weight layout reads as debug output, which is
  /// the register this page is deliberately moving away from.
  ///
  /// It is kept on the constructor because it is the natural thing to pass
  /// here, because it costs nothing, and because a variant that DOES show the
  /// path (the record-card direction) would need it. What must never come back
  /// is `state.error`: that is framework text, not the visitor's input, and
  /// printing it at a stranger who mistyped a URL is the fault this page
  /// replaces.
  final String? location;

  const NotFoundPage({super.key, this.location});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    // The hero's own breakpoint, and for the hero's own reason: this is a
    // two-column layout whose text half stops being readable well before a
    // tablet gets narrow, so the break is set by the CONTENT, not by a device
    // class. See LandingUi.mobileBreak.
    final stacked = width < LandingUi.mobileBreak;

    return Scaffold(
      backgroundColor: LandingUi.surface,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: LandingUi.heroWash),
        child: SafeArea(
          child: Column(
            children: [
              const _NotFoundNav(),
              Expanded(
                child: SingleChildScrollView(
                  // A 404 is short, but it still has to survive a landscape
                  // phone and a browser at 50% zoom with large text. Scrolling
                  // is what stops the CTA being unreachable there — the whole
                  // point of the page is the way out.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: _minBodyHeight(context),
                    ),
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: stacked ? 20 : LandingUi.gutter * 2,
                          vertical: 28,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: LandingUi.contentBand,
                          ),
                          child: stacked
                              ? const _StackedBody()
                              : const _SideBySideBody(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Enough height for [Center] to actually centre against, without forcing a
  /// scrollbar on a short viewport.
  static double _minBodyHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = mq.size.height - mq.padding.vertical - _kNavHeight;
    return h > 0 ? h : 0;
  }
}

const double _kNavHeight = 64;

/// The artwork, sized by the caller.
///
/// ── The asset ───────────────────────────────────────────────────────────────
/// `assets/images/landing/404_error.gif` — LOWERCASE `landing`, matching
/// pubspec and every other landing asset. The file sits in a directory Windows
/// and macOS spell `Landing`, and those are THE SAME DIRECTORY there because
/// the filesystem ignores case; a deploy on a case-sensitive filesystem is not
/// so forgiving, and the lowercase spelling is the one pubspec registers.
///
/// The GIF's background was flood-filled to transparent so it composites
/// straight onto the wash. Its own internal padding is generous, which is why
/// callers pull it in with negative margins rather than sizing it tightly.
class _Artwork extends StatelessWidget {
  final double width;
  const _Artwork({required this.width});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Three people holding up a large 404 sign',
      image: true,
      child: Image.asset(
        'assets/images/landing/404_error.gif',
        width: width,
        fit: BoxFit.contain,
        // A missing asset must never take down the page whose whole job is to
        // be a way out. The copy and the buttons carry the page without it.
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// Wide: copy left, artwork right — the hero's own split.
class _SideBySideBody extends StatelessWidget {
  const _SideBySideBody();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    // One step up at the full content band, where there is room for the
    // artwork to lead rather than merely balance.
    final art = width >= LandingUi.tabletBreak ? 460.0 : 360.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(child: _Copy(centred: false)),
        const SizedBox(width: 32),
        // Flexible, not a fixed SizedBox: between mobileBreak and tabletBreak
        // the row can still be tight, and a rigid child would overflow rather
        // than yield.
        Flexible(
          flex: 0,
          child: _Artwork(width: art),
        ),
      ],
    );
  }
}

/// Narrow: artwork first, copy under it, everything centred.
///
/// The artwork leads here rather than following, because on a phone the first
/// screenful is all most visitors see — and the illustration says "404" faster
/// than the sentence does.
class _StackedBody extends StatelessWidget {
  const _StackedBody();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    // ── Sized against BOTH axes ──────────────────────────────────────────
    // Width alone is not enough. The artwork is square, so on a short viewport
    // — a 320x568 phone, or any phone in landscape — a width-derived size eats
    // the height the copy and the two buttons need, and the CTA ends up below
    // the fold. That is the one failure this page cannot have: its entire
    // purpose is to be a way out.
    //
    // Measured: at 320x568 a 166px artwork put the primary button at y=593,
    // 25px past the bottom edge. Taking the smaller of a width share and a
    // height share keeps the whole column on screen at every phone size, and
    // the width share still governs on a tall phone where there is room.
    final fromWidth = size.width * 0.52;
    final fromHeight = size.height * 0.22;
    final art = (fromWidth < fromHeight ? fromWidth : fromHeight).clamp(
      110.0,
      280.0,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Artwork(width: art),
        const SizedBox(height: 4),
        const _Copy(centred: true),
      ],
    );
  }
}

/// The eyebrow, headline, explanation and the two actions.
class _Copy extends StatelessWidget {
  final bool centred;
  const _Copy({required this.centred});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < LandingUi.mobileBreak;
    final align = centred ? TextAlign.center : TextAlign.start;
    final cross = centred
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cross,
      children: [
        Text(
          'ERROR 404',
          textAlign: align,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.2,
            color: LandingUi.accentBright,
          ),
        ),
        const SizedBox(height: 12),

        // The hero's headline treatment: w800, tight tracking, and the second
        // line carrying colour the way "Better Governance" does.
        Text.rich(
          const TextSpan(
            children: [
              TextSpan(text: 'We lost the signal\n'),
              TextSpan(
                text: 'on this page',
                style: TextStyle(color: LandingUi.accentBright),
              ),
            ],
          ),
          textAlign: align,
          style: TextStyle(
            fontSize: narrow ? 26 : 38,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            // 1.22, not the hero's tighter setting: at w800 a lower value
            // shears the descenders off "signal" and "page".
            height: 1.22,
            color: LandingUi.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        ConstrainedBox(
          // ~60 characters. Running text wider than this stops being
          // comfortable to read, regardless of how much room the column has.
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            'The link may be broken, or the page it pointed to was removed.',
            textAlign: align,
            style: const TextStyle(
              fontSize: 16,
              height: 1.5,
              color: LandingUi.textBody,
            ),
          ),
        ),
        const SizedBox(height: 26),

        _Actions(centred: centred),
      ],
    );
  }
}

/// The two ways out.
///
/// Both work whether or not there is a session, which is the fix for the old
/// page's dead end: "Back to Home" pointed at the signed-in feed, and a
/// signed-out visitor — the likeliest person to hit a 404 — could not go there.
class _Actions extends StatelessWidget {
  final bool centred;
  const _Actions({required this.centred});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      // Wrap, not Row: at 320px with a large text setting the two buttons do
      // not fit side by side, and a Row would paint an overflow stripe across
      // the page. This drops the second button onto its own line instead.
      spacing: 12,
      runSpacing: 12,
      alignment: centred ? WrapAlignment.center : WrapAlignment.start,
      children: [
        ElevatedButton(
          onPressed: () => context.go('/'),
          style: ElevatedButton.styleFrom(
            backgroundColor: LandingUi.ctaGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LandingUi.controlRadius),
            ),
          ),
          child: const Text(
            'Go to GovPulse',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
        ),
        OutlinedButton(
          onPressed: () => context.go('/guest'),
          style: OutlinedButton.styleFrom(
            foregroundColor: LandingUi.textPrimary,
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LandingUi.controlRadius),
            ),
          ),
          child: const Text(
            'Browse as guest',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// A minimal nav: the mark, and a way back.
///
/// NOT [LandingNav]. That one takes `onFeatures` / `onHowItWorks` / `onFaq`
/// callbacks that scroll to sections of the landing page — sections which do
/// not exist here. Wiring them to navigate away would make three nav items
/// that behave unlike every other page's, and passing no-ops would leave dead
/// links on a page whose entire purpose is to be a working exit.
class _NotFoundNav extends StatelessWidget {
  const _NotFoundNav();

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.navCompactBreak;

    return SizedBox(
      height: _kNavHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 26),
        child: Row(
          children: [
            // Flexible, NOT a bare child, and this is the specific trap
            // [BrandMark] documents on itself: the Row inside it is
            // mainAxisSize.min, so it reports its NATURAL width — glyph plus
            // wordmark — however little room it is given, and never learns it
            // is being squeezed. At 320px with the test's wide fallback font
            // that overflowed the bar by up to 250px. Flexible gives it a
            // bounded width, and BrandMark's own FittedBox then scales the
            // lockup down uniformly rather than ellipsising into "GovPul…".
            Flexible(
              // Tappable: on a 404 the mark is a genuine way out, not
              // decoration.
              child: Align(
                // Without this the InkWell fills the Flexible's whole width
                // and the mark sits centred in it, which on a wide screen
                // parked "Sign in" right beside the logo instead of at the
                // far edge. Align keeps the tap target tight to the mark and
                // lets the Spacer below do its job.
                alignment: Alignment.centerLeft,
                child: InkWell(
                  onTap: () => context.go('/'),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: const BrandMark(size: 28),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Never shrinks: "Sign in" is the nav's only other affordance, and
            // a half-rendered one is worse than a smaller brand mark.
            TextButton(
              onPressed: () => context.go('/login'),
              style: TextButton.styleFrom(
                foregroundColor: CitizenUi.textSecondary,
                padding: EdgeInsets.symmetric(horizontal: narrow ? 10 : 16),
              ),
              child: const Text(
                'Sign in',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
