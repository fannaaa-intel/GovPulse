import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Visual tokens for the **staff console**. It follows the GovPulse app palette
/// — the same brand blue and neutral surfaces the admin console uses (see
/// [AppColors.primaryBlue] + AdminUi) — so the staff portal looks like the rest
/// of the product. Kept as its own token set so the staff layout can be tuned
/// without rippling into the citizen app or the admin console.
class StaffUi {
  StaffUi._();

  // ── Accent (app brand blue, same as admin) ───────────────────────────────
  static const Color accent = AppColors.primaryBlue; // 0xFF0D47A1
  static const Color accentSoft = Color(0xFF1976D2); // lighter brand blue
  static const Color accentWash = Color(0xFFEAF1FB); // blue-50 wash

  // ── Surfaces ─────────────────────────────────────────────────────────────
  static const Color pageBg = Color(0xFFF6F8FC);
  static const Color surface = Colors.white;
  static const Color subtle = Color(0xFFF4F6FB);

  // ── Borders ──────────────────────────────────────────────────────────────
  static const Color border = Color(0xFFCBD3DF);
  static const Color borderStrong = Color(0xFFB6C0CE);

  // ── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF4B5563);
  static const Color textMuted = Color(0xFF8A94A6);

  // ── Semantic ─────────────────────────────────────────────────────────────
  static const Color online = Color(0xFF16A34A);
  static const Color offline = Color(0xFF94A3B8);
  static const Color danger = Color(0xFFEF4444);
  static const Color warn = Color(0xFFF39C12);

  // ── Shape ────────────────────────────────────────────────────────────────
  static const double cardRadius = 14;
  static const double controlRadius = 10;

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x141B2A4E), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
