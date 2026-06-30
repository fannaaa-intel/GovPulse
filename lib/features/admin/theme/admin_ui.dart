import 'package:flutter/material.dart';

/// Shared visual tokens for the **admin shell** — the sidebar, the topbar, the
/// dashboard cards, and any future admin nav/surface.
///
/// Kept separate from the global `AppColors` palette: `AppColors` is read across
/// the whole product (citizen app + web), so changing a value there ripples
/// everywhere. These tokens only affect widgets that import *this* file, so the
/// admin console can be tuned in one place without risk to the rest of the app.
class AdminUi {
  AdminUi._();

  // ── Surfaces ───────────────────────────────────────────────────────────────
  /// Page background behind all cards.
  static const Color pageBg = Color(0xFFF6F8FC);

  /// Card / nav / topbar fill.
  static const Color surface = Colors.white;

  /// A faint fill for inset elements (search field, muted chips, chart gridded
  /// areas) so they read as "recessed" against white cards.
  static const Color subtle = Color(0xFFF4F6FB);

  // ── Borders ──────────────────────────────────────────────────────────────
  /// Default hairline for cards, the sidebar edge, the topbar divider.
  /// Kept clearly visible against the light page background — a near-white
  /// line disappears and makes cards bleed into the canvas.
  static const Color border = Color(0xFFCBD3DF);

  /// A touch stronger, for hover/emphasis and inset controls.
  static const Color borderStrong = Color(0xFFB6C0CE);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF4B5563);
  static const Color textMuted = Color(0xFF8A94A6);

  // ── Shape & spacing ──────────────────────────────────────────────────────
  static const double cardRadius = 14;
  static const double controlRadius = 10;

  /// Subtle elevation that gives the console its "web app" depth without the
  /// heavy Material drop-shadow look.
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x141B2A4E), blurRadius: 16, offset: Offset(0, 4)),
  ];
}
