import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Visual tokens for the **citizen web interface** — the top nav, the nav
/// drawer, the Home dashboard sections, NewsFeed, My Reports, Emergency and
/// Settings as they render in a browser.
///
/// Counterpart to `AdminUi` (features/admin/theme) and `StaffUi`
/// (features/staff/theme). Same reasoning as those two: [AppColors] is read by
/// the whole product — the Flutter mobile app included — so retuning a value
/// there ripples somewhere nobody was looking. These tokens only reach widgets
/// that import *this* file, so the citizen web side can be adjusted in one
/// place without touching the mobile app or either console.
///
/// ── Where these values came from ──────────────────────────────────────────
/// Nothing here is a new colour. Every value below was already hardcoded as a
/// hex literal across `core/widgets/Home`, `core/widgets/web` and
/// `features/home`; the count in each comment is how many times that literal
/// appears in those trees today. The brand entries deliberately re-export
/// [AppColors] rather than restating the literal, because the citizen web side
/// already reaches for `AppColors.primaryBlue` 417 times and `AppColors.green`
/// 91 times — those are the accent source of truth and should stay that way.
///
/// Adding a token here is fine. Adding a *new* grey is not: if a surface needs
/// a shade that isn't in this file, it almost certainly wants one that is.
class CitizenUi {
  CitizenUi._();

  // ── Brand ──────────────────────────────────────────────────────────────────
  /// GovPulse blue. Aliased, not redeclared — see the class doc.
  static const Color accent = AppColors.primaryBlue; // 0xFF0D47A1

  /// GovPulse green. Used for verified state, success, positive stats.
  static const Color accentGreen = AppColors.green; // 0xFF2ECC71

  /// Pale blue wash behind selected nav rows, info callouts, active chips.
  static const Color accentWash = Color(0xFFEFF6FF); // ×11

  // ── Surfaces ───────────────────────────────────────────────────────────────
  /// Default page background for the citizen web shell. This is the neutral
  /// grey `ResponsiveNavScaffold` already defaults to, and by far the most
  /// common page fill on the citizen side.
  static const Color pageBg = Color(0xFFF3F4F6); // ×86

  /// Home's page background — the same idea, a hair cooler/bluer.
  ///
  /// Kept as a SEPARATE token rather than folded into [pageBg] because the two
  /// genuinely differ today: Home paints 0xFFF3F6FC while every other
  /// destination paints 0xFFF3F4F6. Collapsing them is a real (small) visual
  /// change to Home, which Phase 0 is explicitly not making. Recording both is
  /// what makes that divergence visible enough to decide about later.
  static const Color pageBgHome = Color(0xFFF3F6FC); // ×3

  /// Card / nav / top-bar fill.
  static const Color surface = Colors.white;

  /// Faint recessed fill for inset elements — search fields, muted rows,
  /// skeleton blocks — so they read as sunk into a white card.
  static const Color subtle = Color(0xFFF9FAFB); // ×16

  // ── Borders ────────────────────────────────────────────────────────────────
  //
  // ── Retuned to match AdminUi and StaffUi ─────────────────────────────────
  // These were #E5E7EB and #D1D5DB — the literals inherited from the mobile
  // screens, where a hairline separates two rows INSIDE a white card and has
  // very little work to do. On the web surface the same hairline is the edge of
  // a white card sitting on [pageBg], and #E5E7EB is only about fourteen steps
  // darker than that background: on a real monitor the card had no visible
  // edge at all, which is what made every bordered field read as plain text.
  //
  // Both consoles had already solved this — AdminUi.border and StaffUi.border
  // are #CBD3DF, and their cards read cleanly — so citizen web was the one
  // surface out of step with the other two. These now match them exactly,
  // which is also why they are not some third new value.
  //
  // Mobile is unaffected by construction: nothing in the app imports this file
  // (see the class doc), and the shared quick-action screens reach for these
  // tokens only from their `splitPanel` web paths.

  /// Default hairline: card edges, the top-nav underline, list dividers.
  static const Color border = Color(0xFFCBD3DF);

  /// A step stronger, for hover, focus and inset controls.
  static const Color borderStrong = Color(0xFFB6C0CE);

  // ── Hairlines for widgets that render on BOTH surfaces ────────────────────
  //
  // [border] above is safe to retune because only web widgets import this file.
  // Most of the citizen surface is not like that: the feed post card, the top
  // nav, My Reports, the loading skeletons and the quick-action screens are ONE
  // widget each, drawn by the mobile app and by the web shell alike. They had
  // their hairline hardcoded, and darkening it in place would have redesigned
  // the mobile app as a side effect of fixing the web one.
  //
  // So the choice is made per-SURFACE rather than per-widget. `kIsWeb` is a
  // compile-time constant, which is what makes this work at all: these stay
  // `const`, so every existing `const BoxDecoration` keeps its constness and
  // the branch is folded away at build time rather than tested at runtime.
  //
  // The mobile arm of each is the literal that site already used — not an
  // approximation of it — so the app renders byte-for-byte what it rendered
  // before. That is the whole point of there being two of these rather than
  // one: #E5E7EB and AppColors.stroke are two units apart and nobody could see
  // the difference, but "provably unchanged" is worth more than one fewer
  // token.

  /// Hairline for a shared widget whose literal was `#E5E7EB`.
  static const Color sharedBorder = kIsWeb ? border : Color(0xFFE5E7EB);

  /// Hairline for a shared widget that reached for [AppColors.stroke].
  static const Color sharedStroke = kIsWeb ? border : AppColors.stroke;

  // ── Text ───────────────────────────────────────────────────────────────────
  /// Headings and primary body copy.
  static const Color textPrimary = Color(0xFF1F2937); // ×98

  /// Secondary copy, nav labels, icon glyphs.
  static const Color textSecondary = Color(0xFF374151); // ×67

  /// Muted supporting copy — subtitles, metadata, timestamps.
  static const Color textMuted = Color(0xFF6B7280); // ×96

  /// Faintest tier — placeholders, disabled state, de-emphasised captions.
  static const Color textFaint = Color(0xFF9CA3AF); // ×104

  // ── Semantic ───────────────────────────────────────────────────────────────
  /// The notification badge / "live" dot green. Brighter than [accentGreen]
  /// and used specifically where a small mark has to read against white.
  static const Color badge = Color(0xFF22C55E); // ×39

  /// Verified-state text green (darker, for copy on a light wash).
  static const Color success = Color(0xFF15803D); // ×11

  static const Color danger = AppColors.red; // 0xFFE74C3C
  static const Color warn = Color(0xFFF59E0B); // ×28

  /// Pending / awaiting-review text amber, the partner to [warn] for copy.
  static const Color pending = Color(0xFFB45309); // ×10

  // ── Shape & elevation ──────────────────────────────────────────────────────
  // Matched to AdminUi / StaffUi so a citizen card and a console card have the
  // same corner and the same weight of shadow.
  static const double cardRadius = 14;
  static const double controlRadius = 10;

  // ── The citizen RECORD BAND ─────────────────────────────────────────────
  //
  // One content measure for every page that shows a citizen's own records —
  // My Reports, My Submissions, the report and submission details, and the
  // account pages. `recordBand` less two `recordGutter`s is 816, and a page
  // landing anywhere else is what made opening a card appear to resize the
  // window.
  //
  // It lives here, beside the radii, rather than in the account kit that names
  // it (kAccountMaxWidth / kAccountPageGutter alias these) because the LOADING
  // SKELETONS need the same number, and the kit already imports the skeletons.
  static const double recordBand = 880;
  static const double recordGutter = 32;

  /// Below [kAccountStackBelow], where 32 a side is a tenth of the screen.
  static const double recordGutterTight = 20;

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x141B2A4E), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
