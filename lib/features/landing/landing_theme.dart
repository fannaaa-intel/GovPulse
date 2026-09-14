import 'package:flutter/material.dart';

import '../../core/theme/citizen_ui.dart';

/// Visual tokens for the PUBLIC landing page.
///
/// ── Why these are not just [CitizenUi] ─────────────────────────────────────
/// [CitizenUi] describes the signed-in product: a dense application surface of
/// cards on grey, tuned so a citizen can scan a feed. The landing page is a
/// different job — it is a marketing page that has to hold a stranger's
/// attention on a phone, so it runs bigger type, more generous vertical rhythm
/// and a white ground with coloured washes.
///
/// The BRAND, though, is shared and must stay shared: every colour below either
/// aliases a [CitizenUi] token or is a wash mixed from one. Nothing here
/// invents a new blue, because the moment the landing page's blue drifts from
/// the app's blue, the handoff from page to product looks like two products.
class LandingUi {
  LandingUi._();

  // ── Brand ─────────────────────────────────────────────────────────────────
  static const Color accent = CitizenUi.accent; // 0xFF0D47A1
  static const Color accentGreen = CitizenUi.accentGreen; // 0xFF2ECC71

  /// The brighter blue the mockup's headline second line uses. Sampled from the
  /// design; sits between the brand navy and the sky wash, which is what lets
  /// "Better Governance" read as emphasis rather than as a different palette.
  static const Color accentBright = Color(0xFF1B6FE0);

  /// The CTA green from the mockup's "Get Started" button. Deeper than
  /// [accentGreen], which is tuned for small verified ticks on white and is too
  /// light to carry white button text accessibly.
  static const Color ctaGreen = Color(0xFF16A34A);

  // ── Ground ────────────────────────────────────────────────────────────────
  static const Color surface = Colors.white;

  /// Alternating section ground, for the bands that must separate from white.
  static const Color sectionAlt = Color(0xFFF7F9FC);

  /// The deep navy of the footer.
  static const Color footerBg = Color(0xFF11294F);
  static const Color footerText = Color(0xFFC7D4E6);
  static const Color footerHeading = Colors.white;

  // ── Hero wash ─────────────────────────────────────────────────────────────
  //
  // SAMPLED FROM THE ARTWORK, NOT INVENTED. The mockup's hero sits on a 6 MB
  // 1920x1080 PNG (assets/images/Landing/Home/1.png) that is nothing but a soft
  // blue gradient with a little dither noise — which is why PNG could not
  // compress it. These five stops are read off that file's corners and centre
  // (see tool/build_landing_assets.py, which deliberately does not convert it),
  // so the gradient below reproduces it for zero bytes.
  //
  // Measured: TL #FCFEFE, TC #C7E3F1, TR #46B2E8, MC #9EE0F1, BR #FFFFFF.
  static const Color washTop = Color(0xFFEAF6FC);
  static const Color washMid = Color(0xFFBFE4F4);
  static const Color washDeep = Color(0xFF7FC9EA);

  /// The hero's background: white at the upper-left, deepening to sky toward
  /// the upper-right, and falling away to white again at the bottom so the
  /// section below joins without a seam.
  static const LinearGradient heroWash = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: <Color>[surface, washTop, washMid, washDeep],
    stops: <double>[0.0, 0.38, 0.72, 1.0],
  );

  /// A far softer version for the closing CTA band, which carries the
  /// blue-to-green sweep of the mockup's last panel.
  static const LinearGradient ctaWash = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[Color(0xFF8FD3F0), Color(0xFF7FE0C0)],
  );

  // ── Type ──────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textBody = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);

  /// The small uppercase label above each section heading ("FEATURES").
  static const Color eyebrow = accentBright;

  // ── Shape ─────────────────────────────────────────────────────────────────
  static const double cardRadius = 16;
  static const double controlRadius = 10;

  /// Content measure. Wider than [CitizenUi.recordBand] because marketing
  /// sections are full-bleed bands rather than a column of records.
  static const double contentBand = 1180;

  /// Page side gutter. Applied once per band — see `_Band` in landing_page.dart.
  static const double gutter = 24;

  /// Width below which the page collapses to a single column.
  ///
  /// 900 rather than a device width: the hero is a two-column layout whose text
  /// half stops being readable well before a tablet gets narrow, so the break
  /// is set by the content rather than by a device class.
  static const double mobileBreak = 900;

  /// Second break, for the three-up rows, which need to fold before the hero
  /// does.
  static const double tabletBreak = 1180;

  /// Width below which the NAV's three anchors move into the overflow menu.
  ///
  /// The nav used to fold at [mobileBreak], which is the HERO's breakpoint —
  /// the width its two-column layout stops working at. The nav's own content
  /// folds much later: measured, the mark, three links, the CTA and their
  /// padding need about 560px, and at 899 the bar has 851. So a 34-inch-wide
  /// browser window one pixel under the hero's break was handing a desktop user
  /// a phone's hamburger with 291px of bar sitting empty beside it.
  ///
  /// 720 leaves ~160px of slack over the measured need, which covers a longer
  /// translation of "How it Works" or a fallback font before anything has to
  /// collapse.
  ///
  /// Below this the bar does NOT go straight to a menu — see [navCompactBreak].
  static const double navBreak = 720;

  /// Width below which the nav's anchors finally move into the overflow menu.
  ///
  /// Between this and [navBreak] the links stay inline in a COMPACT form:
  /// tighter link padding (8 rather than 14), no gaps between them, a smaller
  /// gap before the CTA, and 13.5pt type.
  ///
  /// Both numbers are MEASURED, by forcing each layout into a narrowing slot
  /// and watching for the overflow:
  ///
  ///     full nav      overflows below ~700   →  navBreak       720
  ///     compact nav   overflows below ~600   →  navCompactBreak 620
  ///
  /// 620 rather than 600, for the same reason navBreak is 720 rather than 700:
  /// a breakpoint sitting exactly on the overflow edge has no margin for a
  /// fallback font, a longer translation, or a user's larger text setting — and
  /// this failure mode is a debug overflow stripe across the top of the page.
  ///
  /// The point of the tier is that "does not fit at full size" was being
  /// treated as "does not fit". A 600px window has plenty of bar — more than
  /// half of it was empty — and hiding three short words behind a menu button
  /// there costs a tap for nothing.
  ///
  /// The labels are never abbreviated to make this work. A nav whose wording
  /// changes with the viewport is harder to use than a denser one.
  static const double navCompactBreak = 620;

  /// Width below which the features RING folds into its card grid.
  ///
  /// Lower than [tabletBreak], which the ring used to share. That was set by
  /// the width the ring's slot table was SOLVED at, not by the width it stops
  /// working at — and those turned out to be far apart. Measured by forcing the
  /// ring below its breakpoint (see the table on `_kPhoneFloor` in
  /// landing_features.dart): label pairs stay disjoint down to 900, and what
  /// fails first is labels landing on the device art, which the phone yielding
  /// fixes.
  ///
  /// 940 rather than 900: 900 is the last width that renders cleanly, and a
  /// breakpoint sitting exactly on the failure edge has no margin for a font
  /// fallback or a longer translation. It is also [mobileBreak] + 40, so the
  /// ring never has to survive the width where the whole page restacks.
  static const double ringBreak = 940;

  // ── Elevation ─────────────────────────────────────────────────────────────
  /// The soft lift under a floating card. Deliberately wide and faint — a tight
  /// dark shadow reads as a dialog, not as a marketing card.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x140F172A), blurRadius: 28, offset: Offset(0, 10)),
  ];

  static const List<BoxShadow> navShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 16, offset: Offset(0, 2)),
  ];
}
