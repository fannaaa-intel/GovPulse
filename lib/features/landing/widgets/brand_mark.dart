import 'package:flutter/material.dart';

import '../landing_theme.dart';

/// The GovPulse mark and wordmark, as the design draws it: the "A" glyph, then
/// "Gov" in navy and "Pulse" in blue.
///
/// ── Why the wordmark is TEXT and not the lockup image ──────────────────────
/// `applogocrop.webp` is the stacked lockup with the name already in it, and
/// using it here would mean a bitmap of text — soft on a retina screen, unread
/// by a screen reader, and un-selectable. The glyph is the only part that has
/// to be artwork.
///
/// [onDark] flips the wordmark to white for the footer, which sits on navy.
class BrandMark extends StatelessWidget {
  final double size;
  final bool onDark;

  const BrandMark({super.key, this.size = 32, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // One label for the pair. Without this a screen reader reads the image's
      // own label and then the two text runs, announcing the brand three times.
      label: 'GovPulse',
      container: true,
      excludeSemantics: true,
      // FitBox rather than a bare Row.
      //
      // The Row below is mainAxisSize.min, which makes it report its NATURAL
      // width — glyph plus wordmark — regardless of how little room it is given.
      // A Flexible on the text cannot fix that: min-sizing means the Row never
      // learns it is being squeezed, so at 320px it simply overflowed its
      // parent by 19px, in the footer where it is centred in an unbounded
      // column.
      //
      // scaleDown shrinks the whole lockup uniformly when the space is too
      // tight and leaves it completely alone when it is not — so the mark keeps
      // its exact proportions at every width instead of the wordmark
      // ellipsising into "GovPul…", which on a brand mark is worse than small.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/applogo.webp',
              width: size,
              height: size,
              fit: BoxFit.contain,
              // A missing asset must never take down the one page a stranger
              // judges the product by.
              errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
            ),
            SizedBox(width: size * 0.28),
            // No Flexible and no ellipsis: the FittedBox above scales the whole
            // lockup, so this never has to be squeezed on its own.
            Text.rich(
              TextSpan(
                children: <TextSpan>[
                  TextSpan(
                    text: 'Gov',
                    style: TextStyle(
                      color: onDark ? Colors.white : LandingUi.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: 'Pulse',
                    style: TextStyle(
                      color: onDark ? Colors.white : LandingUi.accentBright,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              style: TextStyle(
                fontSize: size * 0.62,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The App Store / Google Play badges.
///
/// ── Deliberately NOT links, for now ────────────────────────────────────────
/// GovPulse is not published to either store yet — the Android release is
/// blocked on a signing keystore — so there is no URL for these to open. A
/// badge that looks like a button and does nothing when tapped is worse than no
/// badge: it reads as a broken page rather than as a coming-soon.
///
/// So they render at full fidelity as the design intends, and carry a plain
/// "coming soon" affordance instead of a dead tap. When the listings exist,
/// give [storeUrl] a value and they become real links with no other change.
class StoreBadges extends StatelessWidget {
  /// Alignment of the row, which differs between the hero (left on desktop,
  /// centred on mobile) and the closing CTA.
  final WrapAlignment alignment;

  const StoreBadges({super.key, this.alignment = WrapAlignment.start});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: alignment,
      children: const <Widget>[
        _StoreBadge(
          icon: Icons.apple,
          small: 'Download on the',
          large: 'App Store',
        ),
        _StoreBadge(
          icon: Icons.shop_rounded,
          small: 'GET IT ON',
          large: 'Google Play',
        ),
      ],
    );
  }
}

class _StoreBadge extends StatelessWidget {
  final IconData icon;
  final String small;
  final String large;

  const _StoreBadge({
    required this.icon,
    required this.small,
    required this.large,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Coming soon to the $large',
      child: Semantics(
        label: '$large — coming soon',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    small,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 9.5,
                      height: 1.1,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    large,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
