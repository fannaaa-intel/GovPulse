import 'package:flutter/material.dart';

import '../../../../theme/citizen_ui.dart';

/// The shared vocabulary of the citizen web shell's two washed promo cards:
/// [RailVerifyCard] in the 288px left rail, and [HomeAppDownloadCard] in the
/// 312px right sidebar.
///
/// CITIZEN WEB ONLY — both consumers are mounted by `_CitizenShellState`, which
/// only the web router builds. Nothing here is reachable from the mobile app.
///
/// Both cards are the same mockup: a headline and body beside an illustration,
/// a hairline rule, then a green button. They used to agree by transcription —
/// the old verify card carried a doc comment promising it was "deliberately a
/// copy of HomeAppDownloadCard's anatomy", which is exactly the kind of promise
/// that rots the first time one of them is touched alone. Everything the two
/// must share lives here instead, so the geometry cannot drift between the rail
/// and the sidebar.
///
/// What is NOT here is what genuinely differs: the verify card's status pill,
/// its coloured state word and its footnote chip have no counterpart in the
/// download card, so they stay in that file.
class WebPromoCardStyle {
  const WebPromoCardStyle._();

  /// Inner padding. Tightens once the card is narrow enough that 18 on both
  /// sides is a meaningful share of the width.
  static double padFor(double cardWidth) => cardWidth >= 264 ? 18 : 14;

  /// Side length of the square illustration box, or 0 for "drop the artwork".
  ///
  /// A ladder, not a lerp: four tested steps beat a formula that produces a
  /// different half-pixel box at every width. Sized so the text column beside
  /// it never drops under ~126px, which is where the headline starts breaking
  /// one word per line.
  ///
  /// Both real widths — the rail's 288 and the sidebar's 312 — land in the same
  /// 92 band, which is the point: the two cards show the same size picture.
  /// Below ~236 there is no split that leaves both readable, so the artwork
  /// goes entirely and the copy takes the full width.
  static double artFor(double cardWidth) => cardWidth >= 320
      ? 100
      : cardWidth >= 280
      ? 92
      : cardWidth >= 236
      ? 72
      : 0;

  /// Gap between the copy column and the illustration.
  static const double artGap = 10;

  /// `.10` fill under a `.22` border, washed from whatever colour the card is
  /// keyed to — brand green for the download card, the state colour for verify.
  static BoxDecoration decoration(Color tint) => BoxDecoration(
    color: tint.withValues(alpha: .10),
    borderRadius: BorderRadius.circular(CitizenUi.cardRadius),
    border: Border.all(color: tint.withValues(alpha: .22)),
  );

  /// The hairline above the card's closing block.
  static Widget rule(Color tint) => Container(
    width: double.infinity,
    height: 1,
    color: tint.withValues(alpha: .20),
  );

  /// The card's illustration.
  ///
  /// Every asset these cards use is a 512x512 WebP with alpha, so it sits
  /// directly on the wash — no white tile behind it, which is what the mockups
  /// show and what the old glyph-in-a-box needed only because a bare [Icon] had
  /// nothing to anchor it. A square box for a square source, so `contain` never
  /// letterboxes.
  ///
  /// Decorative by default: the headline already says what the card is, and a
  /// screen reader announcing the picture too would just say it twice.
  static Widget art(String asset, double size) => SizedBox(
    width: size,
    height: size,
    child: Image.asset(
      asset,
      fit: BoxFit.contain,
      // 512 source into a 72-100 box; the default `low` visibly aliases the
      // thin stroke marks in the artwork at that reduction.
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    ),
  );

  /// Headline. Colour is deliberately left off so the verify card can paint its
  /// state word in a second colour without re-declaring the metrics.
  static const TextStyle headline = TextStyle(
    fontSize: 15.5,
    height: 1.25,
    letterSpacing: -.2,
    fontWeight: FontWeight.w800,
    color: CitizenUi.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 12,
    height: 1.5,
    color: CitizenUi.textMuted,
  );

  /// The one button both cards use. Green in both — including on the verify
  /// card's red unverified skin, exactly as the mockups have it: the card's
  /// colour describes its STATE, while green is the action's own colour.
  static ButtonStyle button() => FilledButton.styleFrom(
    backgroundColor: CitizenUi.accentGreen,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(vertical: 14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(CitizenUi.controlRadius),
    ),
    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
  );
}
