import 'package:flutter/material.dart';

/// Shared visual tokens for the **admin shell** — the sidebar, the topbar, the
/// dashboard cards, and any future admin nav/surface.
///
/// This is intentionally kept separate from the global `AppColors` palette.
/// `AppColors` is read across the whole product (citizen app + web), so
/// changing a value there ripples everywhere. These tokens only affect widgets
/// that import *this* file, so the admin shell can be tuned in one place
/// without any risk to the rest of the app.
///
/// Define a shell colour once here and every admin surface stays consistent —
/// no more hand-copied hex values drifting apart between the nav and the cards.
class AdminUi {
  AdminUi._();

  /// Hairline border for cards, the sidebar's right edge, and the topbar's
  /// bottom divider. Deliberately a touch darker than the old near-white line
  /// so edges are actually visible against the light shell background.
  static const Color border = Color(0xFFCBD3DF);

  /// Standard corner radius for admin cards/surfaces.
  static const double cardRadius = 14;
}
