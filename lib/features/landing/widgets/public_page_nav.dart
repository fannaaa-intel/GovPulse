import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/citizen_ui.dart';
import '../landing_theme.dart';
import 'brand_mark.dart';

/// Height of [PublicPageNav]. Pages that centre content under it subtract this.
const double kPublicNavHeight = 64;

/// Shared by the 404 page and the public Privacy / Terms / About pages.
/// A minimal nav: the mark, and a way back.
///
/// NOT [LandingNav]. That one takes `onFeatures` / `onHowItWorks` / `onFaq`
/// callbacks that scroll to sections of the landing page — sections which do
/// not exist here. Wiring them to navigate away would make three nav items
/// that behave unlike every other page's, and passing no-ops would leave dead
/// links on a page whose entire purpose is to be a working exit.
class PublicPageNav extends StatelessWidget {
  const PublicPageNav({super.key});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < LandingUi.navCompactBreak;

    return SizedBox(
      height: kPublicNavHeight,
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
