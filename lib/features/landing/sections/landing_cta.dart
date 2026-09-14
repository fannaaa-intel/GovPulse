import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../landing_page.dart' show LandingBand;
import '../landing_theme.dart';
import '../widgets/brand_mark.dart';
import '../widgets/reveal_on_scroll.dart';

/// The closing panel: one last invitation, on the blue-to-green sweep.
///
/// ── Why the phone is clipped, not contained ────────────────────────────────
/// The design has the device running off the bottom edge of the panel, which is
/// what makes the block read as a window onto the product rather than a card
/// with a picture in it. That is a [ClipRRect] with the image aligned to the
/// top and allowed to overflow — see [_CtaPhone]. On a narrow screen the phone
/// is dropped entirely rather than shrunk: at 390px there is no width for both
/// a readable headline and a device, and a 90px-wide phone shows nothing.
class LandingCta extends StatelessWidget {
  const LandingCta({super.key});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.mobileBreak;

    return LandingBand(
      background: LandingUi.surface,
      padding: EdgeInsets.fromLTRB(
        LandingUi.gutter,
        narrow ? 24 : 40,
        LandingUi.gutter,
        narrow ? 48 : 72,
      ),
      child: RevealOnScroll(
        offset: 30,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Container(
            decoration: const BoxDecoration(gradient: LandingUi.ctaWash),
            padding: EdgeInsets.fromLTRB(
              narrow ? 26 : 52,
              narrow ? 36 : 52,
              narrow ? 26 : 52,
              // No bottom padding on wide screens: the phone is meant to reach
              // the edge, and padding under it would leave a band of gradient
              // below the device that breaks the effect.
              narrow ? 36 : 0,
            ),
            child: narrow
                ? const _CtaCopy()
                // ── IntrinsicHeight + stretch ──────────────────────────────
                // The panel's height is set by the COPY, and the phone column
                // then has to be given that full height so [_CtaPhone] can hang
                // from its top and overflow the bottom.
                //
                // `stretch` alone cannot do it here: a Row in a scroll view has
                // unbounded height, so stretching a child gives it an infinite
                // constraint and the copy column cannot size itself against it
                // ("RenderBox was not laid out"). IntrinsicHeight resolves the
                // row to the tallest child's natural height FIRST, which makes
                // the stretch finite.
                //
                // Affordable because the row has two children and runs once.
                : const IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 6,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 52),
                            // centerLeft, not Center: the copy is left-aligned
                            // in this column and a bare Center would also pull
                            // it horizontally to the middle.
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _CtaCopy(),
                            ),
                          ),
                        ),
                        SizedBox(width: 32),
                        Expanded(flex: 4, child: _CtaPhone()),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CtaCopy extends StatelessWidget {
  const _CtaCopy();

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.mobileBreak;
    final align = narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final textAlign = narrow ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          const TextSpan(
            children: <TextSpan>[
              TextSpan(text: 'Start Using GovPulse '),
              TextSpan(
                text: 'Today',
                style: TextStyle(color: LandingUi.accentBright),
              ),
            ],
          ),
          textAlign: textAlign,
          style: TextStyle(
            fontSize: narrow ? 27 : 36,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: LandingUi.textPrimary,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'Join citizens who are staying informed, reporting issues, and '
            'engaging with their communities through a faster and smarter '
            'local government experience.',
            textAlign: textAlign,
            style: const TextStyle(
              fontSize: 15,
              height: 1.65,
              color: Color(0xFF1E3A5F),
            ),
          ),
        ),
        const SizedBox(height: 26),
        FilledButton(
          onPressed: () => context.go('/signup'),
          style: FilledButton.styleFrom(
            backgroundColor: LandingUi.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LandingUi.controlRadius),
            ),
          ),
          child: const Text(
            'Create your account',
            style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Download the app',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF17324F),
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

/// The device, hung from the TOP of the panel and running off its bottom edge.
///
/// ── What was wrong, and why it looked like a clipping bug ──────────────────
/// This was an `Align(bottomCenter)` around a `BoxFit.contain` image, inside an
/// `Expanded`. Every part of that fights the effect the panel is going for.
///
/// `contain` fits the WHOLE phone into whatever box the row hands it, and that
/// box is as tall as the copy column beside it — so the device was squashed to
/// 418x587 when its own proportions (1139x1600) want 587 of height for only 418
/// of width. Nothing was actually clipped: measured, 100% of the image was
/// on screen at every width. It just did not look like it, because the ARTWORK
/// is a phone photographed from its top bezel down, and shrinking it to fit a
/// short box made the screen content unreadable while the bottom stopped short
/// of the panel edge — leaving a band of gradient under it and a device that
/// read as both cut off and floating.
///
/// ── What it does now ───────────────────────────────────────────────────────
/// The image is sized by WIDTH and allowed to be as tall as that width implies,
/// hung from the top of the panel so the notch and the app's header are intact,
/// and left to overflow the panel's bottom — which the [ClipRRect] at the use
/// site then cuts on the panel's own rounded edge. That is the "window onto the
/// product" the design draws: a device you see the top two thirds of, running
/// out of the bottom of the block.
///
/// [OverflowBox] is what permits the overflow: the row gives this column a
/// bounded height, and without it the taller image would simply be compressed
/// back into that bound (or overflow-striped in debug).
class _CtaPhone extends StatelessWidget {
  const _CtaPhone();

  @override
  Widget build(BuildContext context) {
    // OverflowBox with an UNBOUNDED max height, rather than a LayoutBuilder
    // computing the natural height from the width.
    //
    // A LayoutBuilder cannot be used here: it sits inside the IntrinsicHeight
    // at the use site, and a LayoutBuilder has no intrinsic dimensions to
    // report, so the row cannot resolve its own height and the whole panel
    // fails to lay out.
    //
    // Letting the height run unbounded and giving the image `fitWidth` reaches
    // the same result without measuring anything: the image takes the column's
    // width, its height follows from the asset's own ratio, and the extra falls
    // past the panel's bottom edge where the ClipRRect cuts it.
    return OverflowBox(
      alignment: Alignment.topCenter,
      maxHeight: double.infinity,
      child: Image.asset(
        'assets/images/landing/cta_phone.webp',
        // fitWidth, not contain: contain would re-fit the image to the shorter
        // of the two dimensions and undo the whole arrangement.
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}
