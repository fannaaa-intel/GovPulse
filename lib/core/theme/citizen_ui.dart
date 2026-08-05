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
  /// Default hairline: card edges, the top-nav underline, list dividers.
  static const Color border = Color(0xFFE5E7EB); // ×116

  /// A step stronger, for hover, focus and inset controls.
  static const Color borderStrong = Color(0xFFD1D5DB); // ×42

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

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x141B2A4E), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
